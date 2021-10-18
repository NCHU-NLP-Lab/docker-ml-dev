import setuptools

setuptools.setup(
    name="ml_dev_cli",
    version="0.0.1",
    author="Philip Huang",
    author_email="p208p2002@gmail.com",
    description="🧰🛠 out-of-the-box docker images for create remote ML development environment",
    url="https://github.com/NCHU-NLP-Lab/docker-ml-dev",
    packages=setuptools.find_packages(),
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
    ],
    entry_points={
        "console_scripts": ["ml-docker=ml_dev_cli:main"],
    },
    python_requires=">=3.5",
    install_requires=["requests"],
)
