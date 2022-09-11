FROM ubuntu:20.04
MAINTAINER Dan Bryant (daniel.bryant@linux.com)

ENV TZ=Europe/London
ENV DEBIAN_FRONTEND=noninteractive 

# install basic dependencies for tsMuxer Linux build
RUN apt-get update
RUN apt-get install -y nano
RUN apt-get install -y software-properties-common
RUN apt-get install -y apt-transport-https
RUN apt-get install -y build-essential g++-multilib
RUN apt-get install -y libc6-dev libfreetype6-dev zlib1g-dev
RUN apt-get install -y checkinstall gcc
RUN apt-get install -y git patch lzma-dev libxml2-dev libssl-dev python curl wget

# common dependencies
RUN apt-get install -y openssl pkg-config libarchive-tools
RUN mkdir -p /usr/local/src
RUN mkdir -p /opt/AppDir
RUN cd /tmp && wget https://cmake.org/files/v3.16/cmake-3.16.9-Linux-x86_64.tar.gz 
RUN cd /usr/local && bsdtar --strip-components=1 -xf /tmp/cmake-3.16.9-Linux-x86_64.tar.gz

# build clang from source
RUN mkdir -p /usr/local/src/clang/build
RUN cd /tmp && wget https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-12.0.1.zip
RUN cd /usr/local/src/clang && bsdtar --strip-components=1 -xf /tmp/llvmorg-12.0.1.zip
RUN cd /usr/local/src/clang/build && cmake ../llvm \
  -G "Unix Makefiles" \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_ASSERTIONS=OFF \
  -DLLVM_ENABLE_PROJECTS="clang;libcxx;libcxxabi" \
  -DLLVM_TEMPORARILY_ALLOW_OLD_TOOLCHAIN=1
RUN cd /usr/local/src/clang/build && make -j $(nproc --ignore=2)
RUN cd /usr/local/src/clang/build && make install

# MSA dependencies
RUN apt-get update
RUN apt-get install -y pip
RUN pip install aqtinstall
RUN aqt list-qt linux desktop
RUN aqt list-qt linux desktop --arch  6.2.2
RUN aqt list-qt linux desktop --modules 6.2.2 gcc_64
RUN ldd --version ldd
RUN cd /usr/local && aqt install-qt linux desktop 6.2.2 -m qtwebengine qtwebview qtwaylandcompositor qt5compat qtwebchannel qtpositioning
RUN mv /usr/local/6.2.2/gcc_64 /usr/local/qt
ENV PATH="/usr/local/qt/bin:$PATH"
ENV CPATH=/usr/local/qt/include
ENV CMAKE_PREFIX_PATH=/usr/local/qt/lib/cmake
ENV Qt6_DIR=/usr/local/qt/lib/cmake/Qt6
RUN echo /usr/local/qt/lib >> /etc/ld.so.conf
RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y libdrm-dev mesa-common-dev libglu1-mesa-dev curl libcurl4-openssl-dev libxkbcommon-x11-0 \
  libnss3 libnspr4 libxcomposite-dev libxdamage1 libxrender1 libxtst6 libegl-dev libegl1-mesa libxkbfile1 \
  libxrandr2 libfontconfig1 libasound2

# pull latest MSA code from git
RUN cd /usr/local/src && git clone --recursive https://github.com/minecraft-linux/msa-manifest.git msa

# patch MSA UI to support Qt6
RUN cd /usr/local/src/msa/msa-ui-qt && git checkout 1193b63a56ac5cfb000a65b9243e726696a5055c

# make MSA
RUN mkdir -p /usr/local/src/msa/build 
RUN cd /usr/local/src/msa/build && cmake -DENABLE_MSA_QT_UI=ON -DCMAKE_INSTALL_PREFIX=/usr -DQT_VERSION=6 ..
RUN cd /usr/local/src/msa/build && make -j $(nproc --ignore=2)
RUN cd /usr/local/src/msa/build && checkinstall --pkgname msa --maintainer ChristopherHX --pkglicense WTFPL --pkgarch amd64
RUN cd /usr/local/src/msa/build && cp *.deb /opt/

# launcher dependencies
RUN apt-get install -y ca-certificates \
  libssl-dev libpng-dev libx11-dev libxi-dev libcurl4-openssl-dev libudev-dev \
  libevdev-dev libegl1-mesa-dev libssl-dev libasound2 \
  autoconf autotools-dev automake libtool texinfo

# make launcher
RUN cd /usr/local/src && git clone --branch qt6 --recursive https://github.com/minecraft-linux/mcpelauncher-manifest.git mcpelauncher 
RUN git config --global user.email "justdan96@gmail.com" && git config --global user.name "Dan Bryant"

# checkout repo versions from the Flathub installer
# https://github.com/flathub/io.mrarm.mcpelauncher/blob/beta/io.mrarm.mcpelauncher.json#L124
# but there is a commit that breaks some things, that change is reversed in the snapshot/renderdragon branch
# https://discordapp.com/channels/429580677617418240/452451848066957314/1012350801118765108
RUN cd /usr/local/src/mcpelauncher/mcpelauncher-core && git checkout 178bd978865a71c1ce1fad986a0893e75e3c347b

# justdan96-renderdragon2 branch includes patches from the snapshot/renderdragon and master branches
# justdan96-master branch includes patches from Flathub with clang-format ran over all the files
RUN cd /usr/local/src/mcpelauncher/mcpelauncher-client && git checkout master
RUN cd /usr/local/src/mcpelauncher/mcpelauncher-client && git remote set-url origin https://github.com/justdan96/mcpelauncher-client.git
RUN cd /usr/local/src/mcpelauncher/mcpelauncher-client && git pull && git checkout master

RUN mkdir -p /usr/local/src/mcpelauncher/build
RUN cd /usr/local/src/mcpelauncher/build && \
  CC=clang CXX=clang++ cmake .. -Wno-dev -DCMAKE_BUILD_TYPE=Release -DJNI_USE_JNIVM=ON \
  -DBUILD_FAKE_JNI_EXAMPLES=OFF -DCMAKE_INSTALL_PREFIX=/opt/mcpe -DQT_VERSION=5
RUN cd /usr/local/src/mcpelauncher/build && /bin/bash -c "make -j $(nproc --ignore=2)"
RUN cd /usr/local/src/mcpelauncher/build && checkinstall --pkgname mcpelauncher --maintainer ChristopherHX --pkglicense WTFPL --pkgarch amd64
RUN cd /usr/local/src/mcpelauncher/build && cp *.deb /opt/

# launcher UI dependencies
RUN apt-get install -y libprotobuf-dev protobuf-compiler libzip-dev

# make launcher UI 
RUN cd /usr/local/src && git clone --branch qt6 --recursive https://github.com/minecraft-linux/mcpelauncher-ui-manifest.git mcpelauncher-ui
RUN mkdir -p /usr/local/src/mcpelauncher-ui/build
RUN cd /usr/local/src/mcpelauncher-ui/build && cmake -DCMAKE_INSTALL_PREFIX=/opt/mcpe -DLAUNCHER_CHANGE_LOG="<p>Testing</p>" \
  -DLAUNCHER_VERSIONDB_URL=https://raw.githubusercontent.com/minecraft-linux/mcpelauncher-versiondb/master ..
RUN cd /usr/local/src/mcpelauncher-ui/build && /bin/bash -c "make -j $(nproc --ignore=2)"
RUN cd /usr/local/src/mcpelauncher-ui/build && checkinstall --pkgname mcpelauncher-ui --maintainer ChristopherHX --pkglicense WTFPL --pkgarch amd64
RUN cd /usr/local/src/mcpelauncher-ui/build && cp *.deb /opt/

# make extract utility
RUN cd /usr/local/src && git clone https://github.com/minecraft-linux/mcpelauncher-extract.git -b ng
RUN mkdir -p /usr/local/src/mcpelauncher-extract/build
RUN cd /usr/local/src/mcpelauncher-extract/build && /bin/bash -c "cmake -DCMAKE_INSTALL_PREFIX=/opt/mcpe -DBUILD_SHARED_LIBS=NO .."
RUN cd /usr/local/src/mcpelauncher-extract/build && /bin/bash -c "make -j $(nproc --ignore=2)"
RUN cd /usr/local/src/mcpelauncher-extract/build && cp mcpelauncher-extract /opt/mcpe/bin/mcpelauncher-extract
RUN cd /usr/local/src/mcpelauncher-extract/build && cp mcpelauncher-extract /opt/mcpelauncher-extract

# install linuxdeploy and the Qt plugin
RUN curl -sLo /usr/local/bin/linuxdeploy-x86_64.AppImage "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage" 
RUN curl -sLo /usr/local/bin/linuxdeploy-plugin-qt-x86_64.AppImage \
  "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage" 
RUN chmod +x /usr/local/bin/linuxdeploy-x86_64.AppImage
RUN chmod +x /usr/local/bin/linuxdeploy-plugin-qt-x86_64.AppImage

# fix for issue of linuxdeploy in Docker containers
RUN dd if=/dev/zero of=/usr/local/bin/linuxdeploy-x86_64.AppImage conv=notrunc bs=1 count=3 seek=8
RUN dd if=/dev/zero of=/usr/local/bin/linuxdeploy-plugin-qt-x86_64.AppImage conv=notrunc bs=1 count=3 seek=8

# ready AppImage resources
RUN cp /usr/local/src/mcpelauncher-ui/mcpelauncher-ui-qt/Resources/mcpelauncher-icon.svg /opt/mcpelauncher-ui-qt.svg
RUN cp /usr/local/src/mcpelauncher-ui/mcpelauncher-ui-qt/mcpelauncher-ui-qt.desktop /opt/mcpelauncher-ui-qt.desktop
