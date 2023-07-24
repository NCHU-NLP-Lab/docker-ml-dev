FROM cnstark/pytorch:2.0.1-py3.9.17-cuda11.8.0-devel-ubuntu20.04

LABEL maintainer="wenchuan19991111@gmail.com"

#
WORKDIR /

ARG DEBIAN_FRONTEND=noninteractive

# 
RUN apt-get update && apt-get install -y sudo \ 
                                        apt-utils \
                                        wget \
                                        vim \
                                        git \
                                        curl

# ip、ping
RUN apt-get install -y net-tools \
                        iputils-ping

# ssh
RUN apt-get install -y openssh-server
RUN apt-get install -y wget
COPY config_files/ssh_config /etc/ssh/ssh_config
RUN service ssh restart

# fail2ban
RUN apt-get install -y fail2ban
COPY config_files/jail.conf /etc/fail2ban/jail.conf
RUN service fail2ban restart

# script for create user
COPY script_files/docker_start.sh /docker_start.sh
RUN chmod 777 /docker_start.sh

# jupyter
COPY config_files/jupyter_notebook_config.py /root/.jupyter/jupyter_notebook_config.py
RUN pip install jupyterlab

# avoid scp error
RUN rm /etc/bash.bashrc
RUN touch /etc/bash.bashrc

# utf-8 zh_TW
RUN apt-get install -y locales
RUN locale-gen en_US.utf8
RUN echo 'export LANGUAGE="en_US.utf8"' >> /etc/bash.bashrc
RUN echo 'export LANG="en_US.utf8"' >> /etc/bash.bashrc
RUN echo 'export LC_ALL="en_US.utf8"' >> /etc/bash.bashrc
RUN update-locale LANG=en_US.utf8

# nodejs
RUN curl -sL https://deb.nodesource.com/setup_16.x | bash -
RUN sudo apt install nodejs

# vscode-server
RUN npm install -g yarn
RUN curl -fsSL https://code-server.dev/install.sh | sh
ENV SHELL=/bin/bash

#
EXPOSE 22
EXPOSE 8888
EXPOSE 8080

#
ENTRYPOINT /docker_start.sh && /bin/bash
