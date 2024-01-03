# Docker for ML Dev

![Build and Publish](https://github.com/NCHU-NLP-Lab/docker-ml-dev/actions/workflows/build.yml/badge.svg)

Dockerfile for quickly create remote dev env for pytorch & tensorflow

## Install

- [GitHub](https://github.com/NCHU-NLP-Lab/docker-ml-dev)
- [Dokcer Hub](https://hub.docker.com/r/nchunlplab/ml-dev)

## Features

- Jupyter
- [web-vscode (code server)](https://github.com/cdr/code-server)
- ssh
- fail2ban
- pytorch
- tensorflow
- cuda support

## Usage

see the `cli` folder

## Known Issue

- [Can't paste text to terminal](https://github.com/cdr/code-server/issues/1106)
  - try `ctrl+shift+v` or `shift+insert`
 
## Install dependency command not found

```bash PATH=$PATH:/user_data/.local/bin ```
