FROM nvidia/cuda:12.8.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    python3 \
    ca-certificates \
    curl \
    p7zip-full \
    ocl-icd-libopencl1 \
    git \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libpcap-dev \
    libcurl4-openssl-dev \
    pkg-config \
    clinfo \
  && rm -rf /var/lib/apt/lists/*

# Register NVIDIA OpenCL ICD; lib is provided at runtime by NVIDIA container toolkit
RUN mkdir -p /etc/OpenCL/vendors \
  && echo "libnvidia-opencl.so.1" > /etc/OpenCL/vendors/nvidia.icd

ENV HASHCAT_VERSION=7.0.0

RUN curl -L "https://hashcat.net/files/hashcat-${HASHCAT_VERSION}.7z" -o /tmp/hashcat.7z \
  && 7z x /tmp/hashcat.7z -o/opt \
  && ln -s "/opt/hashcat-${HASHCAT_VERSION}/hashcat.bin" /usr/local/bin/hashcat \
  && rm -f /tmp/hashcat.7z

RUN mkdir -p /opt/help_crack
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY local_crack.sh /usr/local/bin/local_crack.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/local_crack.sh

RUN git clone --depth 1 https://github.com/ZerBea/hcxtools.git /tmp/hcxtools \
  && make -C /tmp/hcxtools \
  && make -C /tmp/hcxtools install \
  && rm -rf /tmp/hcxtools

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
