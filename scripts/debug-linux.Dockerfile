FROM ubuntu:24.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       ca-certificates curl sudo \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash debug \
    && printf 'debug ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/debug \
    && chmod 0440 /etc/sudoers.d/debug

COPY debug-linux-container.sh /usr/local/bin/debug-linux

ENV HOME=/home/debug USER=debug SHELL=/bin/bash
ENV PATH=/home/debug/.local/bin:/home/debug/.nix-profile/bin:/home/debug/.local/share/mise/shims:$PATH
USER debug
WORKDIR /home/debug
ENTRYPOINT ["bash", "/usr/local/bin/debug-linux"]
