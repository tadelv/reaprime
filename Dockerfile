FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="$FLUTTER_HOME/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git unzip xz-utils zip ca-certificates \
    libglu1-mesa clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/flutter

RUN if [ ! -x /opt/flutter/bin/flutter ]; then \
      git clone --depth=1 https://github.com/flutter/flutter.git -b stable /opt/flutter; \
    fi

RUN flutter config --enable-linux-desktop \
 && flutter precache --linux

WORKDIR /app
CMD ["bash"]
