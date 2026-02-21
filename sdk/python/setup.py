from setuptools import setup, find_packages

setup(
    name="derainedb",
    version="2.0.0",
    description="Official Python SDK for DeraineDB Vector Engine",
    author="Ricardo Bonilla",
    packages=find_packages(),
    install_requires=[
        "grpcio>=1.60.0",
        "protobuf>=4.25.0",
    ],
    python_requires=">=3.8",
)
