# fastText C++ interface
cimport utils
from interface cimport trainWrapper
from interface cimport loadModelWrapper
from interface cimport FastTextModel

# Python/C++ standart libraries
from libc.stdlib cimport malloc, free
from libcpp.string cimport string
from libcpp.vector cimport vector

# Python module
import os
from model import WordVectorModel
from model import SupervisedModel
from model import ClassifierTestResult as CTRes
from builtins import bytes

# This class wrap C++ class FastTextModel, so it can be accessed via Python
cdef class FastTextModelWrapper:
    cdef FastTextModel fm

    def __cinit__(self):
        self.fm = FastTextModel()

    # dict_* methods is a wrapper for the Dictionary class methods;
    # We can't access dicrectly Dictionary in python because
    # Dictionary class doesn't have a nullary constructor
    def dict_nwords(self):
        return self.fm.dictGetNWords()

    def dict_get_word(self, i):
        cdef string cpp_string
        cpp_string = self.fm.dictGetWord(i)
        return cpp_string.decode('utf-8')

    def dict_nlabels(self):
        return self.fm.dictGetNLabels()

    def dict_get_label(self, i):
        cdef string cpp_string
        cpp_string = self.fm.dictGetLabel(i)
        return cpp_string.decode('utf-8')

    def get_vector(self, word):
        word_bytes = bytes(word, 'utf-8')
        return self.fm.getVectorWrapper(word_bytes)

    def classifier_test(self, test_file, k):
        test_file = bytes(test_file, 'utf-8')
        result = self.fm.classifierTest(test_file, k)
        precision = float(result[0])
        recall = float(result[1])
        nexamples = int(result[2])
        return CTRes(precision, recall, nexamples)

    def classifier_predict(self, text, k, label_prefix):
        cdef vector[string] raw_labels
        text_bytes = bytes(text, 'utf-8')
        labels = []
        raw_labels = self.fm.classifierPredict(text_bytes, k)
        for raw_label in raw_labels:
            label = raw_label.decode('utf-8')
            label = label.replace(label_prefix, '')
            labels.append(label)
        return labels

    def classifier_predict_prob(self, text, k, label_prefix):
        cdef vector[vector[string]] raw_results
        cdef string cpp_str
        text_bytes = bytes(text, 'utf-8')
        labels = []
        probabilities = []
        raw_results = self.fm.classifierPredictProb(text_bytes, k)
        for result in raw_results:
            cpp_str = result[0]
            label = cpp_str.decode('utf-8')
            label = label.replace(label_prefix, '')
            cpp_str = result[1]
            prob = float(cpp_str)
            labels.append(label)
            probabilities.append(prob)
        return list(zip(labels, probabilities))

    @property
    def dim(self):
        return self.fm.dim

    @property
    def ws(self):
        return self.fm.ws

    @property
    def epoch(self):
        return self.fm.epoch

    @property
    def minCount(self):
        return self.fm.minCount

    @property
    def neg(self):
        return self.fm.neg

    @property
    def wordNgrams(self):
        return self.fm.wordNgrams

    @property
    def lossName(self):
        return self.fm.lossName

    @property
    def modelName(self):
        return self.fm.modelName

    @property
    def bucket(self):
        return self.fm.bucket

    @property
    def minn(self):
        return self.fm.minn

    @property
    def maxn(self):
        return self.fm.maxn

    @property
    def lrUpdateRate(self):
        return self.fm.lrUpdateRate

    @property
    def neg(self):
        return self.fm.neg

    @property
    def t(self):
        return self.fm.t

# Load .bin file that generated by fastText
# label_prefix is an optional argument to load the supervised model
# prefix will be removed from the label name and stored in the model.labels
def load_model(filename, label_prefix=''):
    # Initialize log & sigmoid tables
    utils.initTables()

    # Check if the filename is readable
    if not os.path.isfile(filename):
        raise ValueError('fastText: trained model cannot be opened!')

    model = FastTextModelWrapper()
    filename_bytes = bytes(filename, 'utf-8')
    try:
        # How we load the dictionary
        loadModelWrapper(filename_bytes, model.fm)
    except:
        raise Exception('fastText: Cannot load ' + filename +
                ' due to C++ extension failed to allocate the memory')

    model_name = model.fm.modelName
    if model_name == 'skipgram' or model_name == 'cbow':
        words = []
        # We build the dictionary here to support unicode characters
        for i in xrange(model.dict_nwords()):
            word = model.dict_get_word(i)
            words.append(word)
        return WordVectorModel(model, words)
    elif model_name == 'supervised':
        labels = []
        for i in xrange(model.dict_nlabels()):
            label = model.dict_get_label(i)
            # Remove the prefix
            labels.append(label.replace(label_prefix, ''))
        return SupervisedModel(model, labels, label_prefix)
    else:
        raise ValueError('fastText: model name is not valid!')

# Wrapper for train(int argc, char *argv) C++ function in cpp/src/fasttext.cc
def train_wrapper(model_name, input_file, output, label_prefix, lr, dim, ws,
        epoch, min_count, neg, word_ngrams, loss, bucket, minn, maxn, thread,
        lr_update_rate, t, silent=1):

    # Check if the input_file is valid
    if not os.path.isfile(input_file):
        raise ValueError('fastText: cannot load ' + input_file)

    # Check if the output is writeable
    try:
        f = open(output, 'w')
        f.close()
        os.remove(output)
    except IOError:
        raise IOError('fastText: output is not writeable!')

    # Initialize log & sigmoid tables
    utils.initTables()

    # Setup argv, arguments and their values
    py_argv = [b'fasttext', bytes(model_name, 'utf-8')]
    py_args = [b'-input', b'-output', b'-lr', b'-dim', b'-ws', b'-epoch',
            b'-minCount', b'-neg', b'-wordNgrams', b'-loss', b'-bucket',
            b'-minn', b'-maxn', b'-thread', b'-lrUpdateRate', b'-t']
    values = [input_file, output, lr, dim, ws, epoch, min_count, neg,
            word_ngrams, loss, bucket, minn, maxn, thread, lr_update_rate, t]

    # Add -label params for supervised model
    if model_name == 'supervised':
        py_args.append(b'-label')
        values.append(label_prefix)

    for arg, value in zip(py_args, values):
        py_argv.append(arg)
        py_argv.append(bytes(str(value), 'utf-8'))
    argc = len(py_argv)

    # Converting Python object to C++
    cdef int c_argc = argc
    cdef char **c_argv = <char **>malloc(c_argc * sizeof(char *))
    for i, arg in enumerate(py_argv):
        c_argv[i] = arg

    # Run the train wrapper
    trainWrapper(c_argc, c_argv, silent)

    # Load the model
    output_bin = output + '.bin'
    model = load_model(output_bin, label_prefix)

    # Free the log & sigmoid tables from the heap
    utils.freeTables()

    # Free the allocated memory
    # The content from PyString_AsString is not deallocated
    free(c_argv)

    return model

# Learn word representation using skipgram model
def skipgram(input_file, output, lr=0.05, dim=100, ws=5, epoch=5, min_count=5,
        neg=5, word_ngrams=1, loss='ns', bucket=2000000, minn=3, maxn=6,
        thread=12, lr_update_rate=100, t=1e-4, silent=1):
    label_prefix = ''
    return train_wrapper('skipgram', input_file, output, label_prefix, lr,
            dim, ws, epoch, min_count, neg, word_ngrams, loss, bucket, minn,
            maxn, thread, lr_update_rate, t, silent)

# Learn word representation using CBOW model
def cbow(input_file, output, lr=0.05, dim=100, ws=5, epoch=5, min_count=5,
        neg=5, word_ngrams=1, loss='ns', bucket=2000000, minn=3, maxn=6,
        thread=12, lr_update_rate=100, t=1e-4, silent=1):
    label_prefix = ''
    return train_wrapper('cbow', input_file, output, label_prefix, lr, dim,
            ws, epoch, min_count, neg, word_ngrams, loss, bucket, minn, maxn,
            thread, lr_update_rate, t, silent)

# Train classifier
def supervised(input_file, output, label_prefix='__label__', lr=0.1, dim=100,
        ws=5, epoch=5, min_count=1, neg=5, word_ngrams=1, loss='softmax',
        bucket=0, minn=0, maxn=0, thread=12, lr_update_rate=100,
        t=1e-4, silent=1):
    return train_wrapper('supervised', input_file, output, label_prefix, lr,
            dim, ws, epoch, min_count, neg, word_ngrams, loss, bucket, minn,
            maxn, thread, lr_update_rate, t, silent)
