"""Empacota limpeza.py para os workers do Dataflow (run.sh passa --setup_file)."""
from setuptools import setup

setup(name="fraudflow-streaming", version="2.0", py_modules=["limpeza"])
