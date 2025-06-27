FROM registry.access.redhat.com/ubi8/ubi:8.10-1184.1741863532 AS crosstoolng

LABEL maintainer="Conan.io <info@conan.io>"

RUN yum install -y \
    autoconf \
    automake \
    bzip2 \
    ca-certificates \
    diffutils \
    file \
    findutils \
    gawk \
    gcc \
    gcc-c++ \
    git \
    glibc-static \
    help2man \
    libstdc++-static \
    libtool \
    libtool-ltdl \
    make \
    ncurses-devel \
    patch \
    perl \
    python3 \
    sudo \
    time \
    unzip \
    wget \
    xz \
    xz-libs

WORKDIR /root

# gettext (for autopoint)
RUN wget -q https://ftp.gnu.org/pub/gnu/gettext/gettext-0.22.5.tar.gz \
    && tar xzf gettext-0.22.5.tar.gz -C /root \
    && cd gettext-0.22.5 \
    && ./configure \
    && make -j \
    && make install

# flex
RUN wget -q https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz \
    && tar xzf flex-2.6.4.tar.gz -C /root \
    && cd flex-2.6.4 \
    && ./configure \
    && make -j \
    && make install

# texinfo
RUN wget -q https://ftp.gnu.org/gnu/texinfo/texinfo-7.2.tar.xz \
    && tar -xf texinfo-7.2.tar.xz -C /root \
    && cd texinfo-7.2 \
    && ./configure \
    && make -j \
    && make install

# bison
RUN wget -q https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.gz \
    && tar xzf bison-3.8.2.tar.gz -C /root \
    && cd bison-3.8.2 \
    && ./configure \
    && make -j \
    && make install

ARG CROSSTOOLNG_VERSION=1.27.0

RUN wget -q http://crosstool-ng.org/download/crosstool-ng/crosstool-ng-${CROSSTOOLNG_VERSION}.tar.xz \
    && tar -Jxf crosstool-ng-${CROSSTOOLNG_VERSION}.tar.xz

# INFO: Generate the configure script
RUN cd /root/crosstool-ng-${CROSSTOOLNG_VERSION} \
    && ./bootstrap

WORKDIR /root/crosstool-ng-${CROSSTOOLNG_VERSION}/build

# INFO: Build ct-ng and install configuration files required by the toolchain
RUN ../configure --prefix=/opt/crosstool-ng-install \
    && make -j \
    && make install

COPY crosstool.config /root/crosstool-ng-${CROSSTOOLNG_VERSION}/build/.config
COPY patches/ /root/crosstool-ng-${CROSSTOOLNG_VERSION}/build/patches

# INFO: Build the toolchain - It takes +30 minutes
# INFO: Install the toolchain automatically in /opt/x-tools
RUN ./ct-ng build

FROM ubuntu:24.04 AS conan

WORKDIR /root/conan

RUN apt-get update && apt-get install -y --no-install-recommends --no-install-suggests \
    ca-certificates \
    make \
    perl \
    pkg-config \
    python3 \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

ARG CONAN_VERSION=2.14.0
ARG CMAKE_VERSION=3.31.8

# INFO: Install Cmake binaries
RUN cd /tmp/ && wget -q https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz \
    && tar -xzf /tmp/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz -C /opt/ \
    && rm /tmp/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz \
    && ln -s /opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin/cmake /usr/local/bin/cmake

# INFO: Install Conan from autocontained installer so we do not need to install Python and pip
RUN wget -q https://github.com/conan-io/conan/releases/download/${CONAN_VERSION}/conan-${CONAN_VERSION}-linux-x86_64.tgz \
    && tar -xvf conan-${CONAN_VERSION}-linux-x86_64.tgz \
    && rm conan-${CONAN_VERSION}-linux-x86_64.tgz \
    && mkdir -p /opt/conan \
    && mv bin /opt/conan \
    && chmod +x /opt/conan/bin/conan \
    && printf '/opt/conan/bin/_internal/\n' >> /etc/ld.so.conf.d/conan.conf \
    && ldconfig \
    && ln -s /opt/conan/bin/conan /usr/local/bin/conan

COPY --from=crosstoolng /opt/x-tools /opt/x-tools

# INFO: Create symlinks for the toolchain binaries.
# Some projectes (e.g. flex) expect gcc installed in PATH. Using CC=.../x86_64-linux-gnu-gcc does not work
# readelf needed by libmysqlclient - envvar READELF does not work
# ar needed by Qt5 -  envvar AR does not work
RUN update-alternatives --install /usr/local/bin/gcc gcc /opt/x-tools/x86_64-linux-gnu/bin/x86_64-linux-gnu-gcc 100 \
    && update-alternatives --install /usr/local/bin/g++ g++ /opt/x-tools/x86_64-linux-gnu/bin/x86_64-linux-gnu-g++ 100 \
    && update-alternatives --install /usr/local/bin/readelf readelf /opt/x-tools/x86_64-linux-gnu/bin/x86_64-linux-gnu-readelf 100 \
    && update-alternatives --install /usr/local/bin/ar ar /opt/x-tools/x86_64-linux-gnu/bin/x86_64-linux-gnu-ar 100

# INFO: Detect default Conan profile and create Conan cache folder
# Not all projects (e.g. Boost) use CC or CXX, so we need to configure them
# The the triplet, the ar and ld executables will not be found by default (e.g. libstacktrace)
# ranlib needed by libselinux and nm needed by wayland
RUN conan profile detect \
    && printf 'core.sources:download_cache=/root/.conan2/download_cache\n' >> /root/.conan2/global.conf \
    && printf '[conf]\ntools.build:verbosity=verbose\ntools.compilation:verbosity=verbose\n' >> /root/.conan2/profiles/default \
    && printf 'tools.build:compiler_executables={"c":"/opt/x-tools/x86_64-linux-gnu/bin/x86_64-linux-gnu-gcc", "cpp":"/opt/x-tools/x86_64-linux-gnu/bin/x86_64-linux-gnu-g++"}\n' >> /root/.conan2/profiles/default \
    && printf '[buildenv]\nAR=/opt/x-tools/x86_64-linux-gnu/bin/x86_64-linux-gnu-ar\n' >> /root/.conan2/profiles/default \
    && printf 'LD=/opt/x-tools/x86_64-linux-gnu/bin/x86_64-linux-gnu-ld\n' >> /root/.conan2/profiles/default \
    && printf 'RANLIB=/opt/x-tools/x86_64-linux-gnu/bin/x86_64-linux-gnu-ranlib\n' >> /root/.conan2/profiles/default \
    && printf 'NM=/opt/x-tools/x86_64-linux-gnu/bin/x86_64-linux-gnu-nm\n' >> /root/.conan2/profiles/default \
    && printf 'STRIP=/opt/x-tools/x86_64-linux-gnu/bin/x86_64-linux-gnu-strip\n' >> /root/.conan2/profiles/default \
    && conan profile show -pr default
