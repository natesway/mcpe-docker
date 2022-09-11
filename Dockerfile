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
RUN aqt list-qt linux desktop --arch  5.15.2
RUN aqt list-qt linux desktop --modules 5.15.2 gcc_64
RUN ldd --version ldd
# debug_info qtcharts qtdatavis3d qtlottie qtnetworkauth qtpurchasing qtquick3d qtquicktimeline qtscript qtvirtualkeyboard qtwaylandcompositor qtwebengine qtwebglplugin
RUN cd /usr/local && aqt install-qt linux desktop 5.15.2 -m qtwebengine qtwebglplugin
RUN mv /usr/local/5.15.2/gcc_64 /usr/local/qt
ENV PATH="/usr/local/qt/bin:$PATH"
ENV CPATH=/usr/local/qt/include
ENV CMAKE_PREFIX_PATH=/usr/local/qt/lib/cmake
ENV Qt5_DIR=/usr/local/qt/lib/cmake/Qt5
RUN echo /usr/local/qt/lib >> /etc/ld.so.conf
RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y libdrm-dev mesa-common-dev libglu1-mesa-dev curl libcurl4-openssl-dev libxkbcommon-x11-0 \
  libnss3 libnspr4 libxcomposite-dev libxdamage1 libxrender1 libxtst6 libegl-dev libegl1-mesa libxkbfile1 \
  libxrandr2 libfontconfig1 libasound2

# pull latest MSA code from git
RUN cd /usr/local/src && git clone --recursive https://github.com/minecraft-linux/msa-manifest.git msa

# patch MSA UI to support Qt6
RUN cd /usr/local/src/msa/msa-ui-qt && git checkout master && git pull

# make MSA
RUN mkdir -p /usr/local/src/msa/build 
RUN cd /usr/local/src/msa/build && cmake -DENABLE_MSA_QT_UI=ON -DCMAKE_INSTALL_PREFIX=/usr -DQT_VERSION=5 ..
RUN cd /usr/local/src/msa/build && make -j $(nproc --ignore=2)
RUN cd /usr/local/src/msa/build && checkinstall --pkgname msa --maintainer ChristopherHX --pkglicense WTFPL --pkgarch amd64
RUN cd /usr/local/src/msa/build && cp *.deb /opt/

# launcher dependencies
RUN apt-get install -y ca-certificates \
  libssl-dev libpng-dev libx11-dev libxi-dev libcurl4-openssl-dev libudev-dev \
  libevdev-dev libegl1-mesa-dev libssl-dev libasound2 \
  autoconf autotools-dev automake libtool texinfo

# make launcher
RUN cd /usr/local/src && git clone --branch ng --recursive https://github.com/minecraft-linux/mcpelauncher-manifest.git mcpelauncher 

# reverse commit that breaks some things
# https://discordapp.com/channels/429580677617418240/452451848066957314/1012350801118765108
# COPY empty_libglesv2.patch /usr/local/src/mcpelauncher/mcpelauncher-core/empty_libglesv2.patch

# checkout repo versions from the Flathub installer
# https://github.com/flathub/io.mrarm.mcpelauncher/blob/beta/io.mrarm.mcpelauncher.json#L124
RUN cd /usr/local/src/mcpelauncher/mcpelauncher-core && git checkout cc06087170a51e415f68f21985eb49c3070e5f97
RUN cd /usr/local/src/mcpelauncher/mcpelauncher-client && git checkout c521350d71f43feefc876074fe7991866c4edd45

# patch some files, apparently necessary for 1.19 support
# https://github.com/flathub/io.mrarm.mcpelauncher/blob/beta/io.mrarm.mcpelauncher.json#L146
RUN cd /usr/local/src/mcpelauncher &&  sed -i -e "s/.*setupGLES2Symbols.*//g" mcpelauncher-client/src/main.cpp
RUN cd /usr/local/src/mcpelauncher &&  sed -i -e "s/.*modLoader;.*/     MinecraftUtils::setupGLES2Symbols(fake_egl::eglGetProcAddress);\0/g" mcpelauncher-client/src/main.cpp
RUN cd /usr/local/src/mcpelauncher &&  sed -i -e "s/.*syms;.*/\0    struct ___data {\n          size_t arena; \n             \n            size_t ordblks; \n             \n            size_t smblks; \n             \n            size_t hblks; \n             \n            size_t hblkhd; \n             \n            size_t usmblks; \n             \n            size_t fsmblks; \n             \n            size_t uordblks; \n             \n            size_t fordblks; \n             \n            size_t keepcost;\n                };\n    android_syms[\"mallinfo\"] = (void*)+[](void*) -> ___data {\n        return { .ordblks = 8000000, .usmblks= 8000000, .fordblks= 8000000 };\n    };/g" mcpelauncher-client/src/main.cpp
RUN cd /usr/local/src/mcpelauncher &&  sed -i "48,57d" mcpelauncher-client/src/fake_looper.cpp
RUN cd /usr/local/src/mcpelauncher &&  sed -i -e "s/.*ALooper_prepare.*/     Log::info(\"Launcher\", \"Loading gamepad mappings\");\n    WindowCallbacks::loadGamepadMappings();\n#ifdef MCPELAUNCHER_ENABLE_ERROR_WINDOW\n    GameWindowManager::getManager()->setErrorHandler(std::make_shared<ErrorWindow>());\n#endif\n\n    Log::info(\"Launcher\", \"Creating window\");\n    static auto associatedWindow = GameWindowManager::getManager()->createWindow(\"Minecraft\",\n            options.windowWidth, options.windowHeight, options.graphicsApi);\0/g" mcpelauncher-client/src/fake_looper.cpp
RUN cd /usr/local/src/mcpelauncher &&  sed -i "s/.*currentLooper =.*/\0currentLooper->associatedWindow = associatedWindow;associatedWindow->makeCurrent(false);/g" mcpelauncher-client/src/fake_looper.cpp
RUN cd /usr/local/src/mcpelauncher &&  sed -i -e "s/useDirectKeyboardInput =.*/useDirectKeyboardInput = false;/g" mcpelauncher-client/src/window_callbacks.cpp
RUN cd /usr/local/src/mcpelauncher/mcpelauncher-client && git diff > /opt/flat.patch
RUN cd /usr/local/src/mcpelauncher/mcpelauncher-client && git diff

RUN mkdir -p /usr/local/src/mcpelauncher/build
RUN cd /usr/local/src/mcpelauncher/build && \
  CC=clang CXX=clang++ cmake .. -Wno-dev -DCMAKE_BUILD_TYPE=Release -DJNI_USE_JNIVM=ON \
  -DBUILD_FAKE_JNI_EXAMPLES=OFF -DCMAKE_INSTALL_PREFIX=/usr
RUN cd /usr/local/src/mcpelauncher/build && /bin/bash -c "make -j $(nproc --ignore=2)"
RUN cd /usr/local/src/mcpelauncher/build && checkinstall --pkgname mcpelauncher --maintainer ChristopherHX --pkglicense WTFPL --pkgarch amd64
RUN cd /usr/local/src/mcpelauncher/build && cp *.deb /opt/

# launcher UI dependencies
RUN apt-get install -y libprotobuf-dev protobuf-compiler libzip-dev

# make launcher UI 
RUN cd /usr/local/src && git clone --recursive https://github.com/minecraft-linux/mcpelauncher-ui-manifest.git mcpelauncher-ui
RUN cd /usr/local/src/mcpelauncher-ui && git checkout ng && git pull && git submodule update 
RUN mkdir -p /usr/local/src/mcpelauncher-ui/build
RUN cd /usr/local/src/mcpelauncher-ui/build && /bin/bash -c "cmake -DCMAKE_INSTALL_PREFIX=/usr .."
RUN cd /usr/local/src/mcpelauncher-ui/build && /bin/bash -c "make -j $(nproc --ignore=2)"
RUN cd /usr/local/src/mcpelauncher-ui/build && checkinstall --pkgname mcpelauncher-ui --maintainer ChristopherHX --pkglicense WTFPL --pkgarch amd64
RUN cd /usr/local/src/mcpelauncher-ui/build && cp *.deb /opt/

# make extract utility
RUN cd /usr/local/src && git clone https://github.com/minecraft-linux/mcpelauncher-extract.git -b ng
RUN mkdir -p /usr/local/src/mcpelauncher-extract/build
RUN cd /usr/local/src/mcpelauncher-extract/build && /bin/bash -c "cmake -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SHARED_LIBS=NO .."
RUN cd /usr/local/src/mcpelauncher-extract/build && /bin/bash -c "make -j $(nproc --ignore=2)"
RUN cd /usr/local/src/mcpelauncher-extract/build && cp mcpelauncher-extract /usr/bin/mcpelauncher-extract
RUN cd /usr/local/src/mcpelauncher-extract/build && cp mcpelauncher-extract /opt/mcpelauncher-extract

# install linuxdeploy and the Qt plugin
RUN curl -sLo /usr/local/bin/linuxdeploy-x86_64.AppImage "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
RUN curl -sLo /usr/local/bin/linuxdeploy-plugin-qt-x86_64.AppImage "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage"
RUN chmod +x /usr/local/bin/linuxdeploy-x86_64.AppImage
RUN chmod +x /usr/local/bin/linuxdeploy-plugin-qt-x86_64.AppImage

# fix for issue of linuxdeploy in Docker containers
RUN dd if=/dev/zero of=/usr/local/bin/linuxdeploy-x86_64.AppImage conv=notrunc bs=1 count=3 seek=8
RUN dd if=/dev/zero of=/usr/local/bin/linuxdeploy-plugin-qt-x86_64.AppImage conv=notrunc bs=1 count=3 seek=8

# ready AppImage resources
RUN cp /usr/local/src/mcpelauncher-ui/mcpelauncher-ui-qt/Resources/mcpelauncher-icon.svg /opt/mcpelauncher-ui-qt.svg
RUN cp /usr/local/src/mcpelauncher-ui/mcpelauncher-ui-qt/mcpelauncher-ui-qt.desktop /opt/mcpelauncher-ui-qt.desktop
