FROM nvidia/cuda:13.4.3-cudnn-devel-ubuntu24.04

RUN apt update && \
    apt install -y \
        wget build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev \
        libreadline-dev libffi-dev libsqlite3-dev libbz2-dev liblzma-dev && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /temp

# download python
RUN wget https://www.python.org/ftp/python/3.13.0/Python-3.13.0.tgz && \
    tar -xvf Python-3.13.0.tgz

# install python
RUN cd Python-3.13.0 && \
    ./configure --enable-optimizations && \
    make && \
    make install

WORKDIR /workspace

RUN rm -r /temp && \
    ln -s /usr/local/bin/python3 /usr/local/bin/python && \
    ln -s /usr/local/bin/pip3 /usr/local/bin/pip

# install pytorch
RUN pip install --upgrade pip && \
    pip install torch==2.15 torchvision==0.29.2 torchaudio==2.11.1 --extra-index-url https://download.pytorch.org/whl/cu134 && \
    rm -r /root/.cache/pip

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

#
EXPOSE 22

#
ENTRYPOINT /docker_start.sh && /bin/bash
