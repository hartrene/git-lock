# This file builds a docker image to run the git-lock server.
# The build will add the git-lock server binaries to the image
# from target/server.tar which will be generated by make.

# build image: $ docker build -t gitlock .
# run container: $ docker run -d -p 2222:22 --name gitlock gitlock
# add pubkek: $ docker exec -i -t gitlock /bin/bash
#             $ echo "yourkey" >> /home/gitlock/.ssh/authorized_keys

FROM ubuntu:16.04

# add openssh
RUN apt-get update
RUN apt-get install -y vim openssh-server
RUN mkdir /var/run/sshd
RUN echo "PermitUserEnvironment yes" >> /etc/ssh/sshd_config

# setup the gitlock user
RUN addgroup gitlock && useradd -g gitlock -m gitlock
RUN cd /home/gitlock && \
	mkdir .ssh && \
	chmod 700 .ssh && \
	echo "# add team member public keys here" > .ssh/authorized_keys && \
	chmod 600 .ssh/authorized_keys && \
	chown -R gitlock:gitlock .ssh

# add gitlock binaries
ADD target/server.tar /home/gitlock
RUN chown -R gitlock:gitlock /home/gitlock/bin
RUN chmod -R u+x /home/gitlock/bin/*

# setup the gitlock environment variables when user ssh into the host
RUN echo "LOCK_SERVER_BIN_DIR=/home/gitlock/bin" > /home/gitlock/.ssh/environment
RUN echo "LOCK_SERVER_DIR=/home/gitlock/lock-working-dir" >> /home/gitlock/.ssh/environment

EXPOSE 22
CMD ["/usr/sbin/sshd","-D"]
