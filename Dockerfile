# Start from ubuntu
FROM ubuntu:20.04

# Update repos and install dependencies
RUN apt-get update \
  && apt-get -y upgrade \
  && apt-get -y install curl git libssl-dev \
    python3-dev python3-pip gzip locales \
    build-essential libsqlite3-dev zlib1g-dev \
    gettext-base

# Set locale for UTF 8 encoding in shell
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Install python packages
RUN mkdir -p /etl-src
WORKDIR /etl-src
COPY . /etl-src
RUN pip3 install -r requirements.txt

# Installing Node
SHELL ["/bin/bash", "--login", "-i", "-c"]
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
RUN source /root/.bashrc && nvm install 16 && npm i -g mapshaper && npm install
SHELL ["/bin/bash", "--login", "-c"]

# Install rust, cargo, and xsv
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
RUN /bin/bash -c "source $HOME/.cargo/env \
  && cargo install xsv"

# Clone tippecanoe source to temporary directory
WORKDIR /
RUN mkdir -p /tmp/tippecanoe-src
RUN git clone -b 1.36.0 https://github.com/mapbox/tippecanoe.git /tmp/tippecanoe-src
WORKDIR /tmp/tippecanoe-src

# Build tippecanoe
RUN git checkout -b master && \
  make && \
  make install

# Remove the temp directory
WORKDIR /
RUN rm -rf /tmp/tippecanoe-src

# Add cargo to path
ENV PATH="/root/.cargo/bin:$PATH"

WORKDIR /etl-src

ENTRYPOINT ["/bin/bash"]
