FROM nvidia/cudagl:11.4.1-devel-ubuntu20.04

RUN rm /etc/apt/sources.list.d/cuda.list
RUN echo "deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64 /" | tee /etc/apt/sources.list.d/cuda.list
RUN apt-key del 3bf863cc
RUN apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/3bf863cc.pub
RUN apt-key del 7fa2af80
RUN apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/7fa2af80.pub
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && apt install -y curl python3.8-venv python-is-python3
RUN apt update && apt install -y mesa-utils xserver-xorg
RUN apt update && apt install -y python3.8-dev

RUN groupadd -g 1000 ubuntu
RUN useradd -rm -d /app -s /bin/bash -g root -G 1000 -u 1000 ubuntu
USER ubuntu
WORKDIR /app
