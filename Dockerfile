FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    curl git unzip xz-utils zip \
    libglu1-mesa clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Create mount point for cached Flutter SDK
RUN mkdir -p /opt/flutter

# Only clone Flutter if it's not already in the cache volume
RUN if [ ! -d /opt/flutter/bin ]; then \
      git clone https://github.com/flutter/flutter.git -b stable /opt/flutter; \
    fi

ENV PATH="/opt/flutter/bin:${PATH}"

# Pre-cache Flutter Linux desktop support
RUN flutter config --enable-linux-desktop && flutter precache --linux

WORKDIR /app
CMD ["bash"]
