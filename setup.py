from setuptools import setup
from Cython.Build import cythonize

setup(
    name='nvme',
    version='0.0.1',
    setup_requires=[
        'setuptools>=45.0',
        'Cython',
    ],
    ext_modules = cythonize('nvme.pyx')
)
