SHELL=/bin/bash

DOMAIN ?= docker.yoshrek.com
EMAIL ?= wkbase@gmail.com


start-docksrvr:
	@echo "Starting Local Docker Container Registry Server ... "
	docker compose -f ./docker-compose.yml up -d
	@echo "Local Docker Container Registry Server is up and Running ... "
	sudo netstat -plnt
	docker ps

clean-docksrvr:
	docker images ls -a ; docker container ls -la ; docker volume ls ; docker network ls; docker ps -a
	docker stop $$(docker ps -qa) || true # true for makefile to proceed ignoring $?=1 exit status
	docker container ls -la | awk '{print $$1}' | grep -v "CONTAINER" | xargs docker container rm || true
	docker images -a | awk '{print $$3}' | grep -v "IMAGE" | xargs docker image remove || true
	docker volume rm $$(docker volume ls -q) ;  docker image prune -af
	docker container prune -af ; docker volume prune -af ; docker system prune -af
	docker images ls -a ; docker container ls -la ; docker volume ls ; docker network ls; docker ps -a

clean-all: clean-docksrvr
	@echo "Cleaned both Native/Local and Docker Deployments"

setup-dockclnt:
	$(MAKE) setup-ssh
	@echo "Copy text from DockerEC2:/home/ubuntu/.ssh/id_rsa.pub and paste to SrikEC2:/home/ubuntu/.ssh/authorized_keys"
	@echo "^^- AND -vv"
	@echo "Copy text from SrikEC2:/home/ubuntu/.ssh/id_rsa.pub and paste to DockerEC2:/home/ubuntu/.ssh/authorized_keys"
	@echo "Then run make setup-dockclnt-rem"

setup-dockclnt-rem:
	$(MAKE) scp-sshclnt
	$(MAKE) setup-sshclnt
	@echo "                                "
	@echo "Execute 'docker login docker.yourdomain.com' and enter user and password details as: "
	@echo " User: testuser, Password: password"
	@echo "                                "
	@echo "Pull busybox image and push to Docker Registry EC2 using below commands: ..."
	@echo "  docker pull busybox           "
	@echo "  docker docker image tag busybox docker.yourdomain.com/sri-busybox           "
	@echo "  docker push docker.yourdomain.com/sri-busybox           "
	@echo "                                "
	@echo "                                "
	@echo "  On the Docker Registry EC2, you can pull the pushed image from the Client EC2 with the below commands: "
	@echo "   docker login docker.yourdomain.com    "
	@echo "   docker pull docker.yourdomain.com/sri-busybox      "
	@echo "   docker images                "
	@echo "                                "




scp-sshclnt:
	@echo "Enter the password given for Docker Registery Server EC2 i.e coolawspassphrase"
	scp ${DOMAIN}:${PWD}/certs/domain.crt ./

setup-sshclnt:
	sudo mkdir -p /etc/docker/certs.d/${DOMAIN}/
	sudo cp ./domain.crt /etc/docker/certs.d/${DOMAIN}/
	wget -qO- http://instance-data/latest/meta-data/public-ipv4; echo

setup-docksrvr: setup-ssh setup-gpg setup-dockcred setup-pass setup-htpasswd setup-openssl
	@echo "                    "
	@echo "                    "
	@echo " ================== "
	@echo "Make Sure to up date your DNS entries i.e docker.youdomain.com to point to below IP-Address: ..."
	wget -qO- http://instance-data/latest/meta-data/public-ipv4; echo
	@echo " ================== "
	@echo "                    "

setup-ssh:
	# Required for openssl, docker registry server, check ec2software.sh for redundancies
	# sudo apt install gpg pass apache2-utils make
	ssh-keygen -q -t rsa -N 'coolawspassphrase' -f ~/.ssh/id_rsa <<<y >/dev/null 2>&1

setup-dockcred:
	wget https://github.com/docker/docker-credential-helpers/releases/download/v0.6.3/docker-credential-pass-v0.6.3-amd64.tar.gz
	tar -zxvf docker-credential-pass-v0.6.3-amd64.tar.gz
	chmod a+x docker-credential-pass
	sudo mv docker-credential-pass /usr/bin
	rm -rf docker-credential*

setup-htpasswd:
	sudo rm -rf auth
	mkdir -p auth
	htpasswd -Bbn testuser password > auth/htpasswd

setup-openssl:
	sudo rm -rf certs
	mkdir -p certs
	# The Flag -addext subjectAltName is compulsory for 'docker login docker.domain.com" to work
	openssl req -newkey rsa:4096 -nodes -sha256 -addext "subjectAltName = DNS:${DOMAIN}" -subj "/C=US/ST=CA/L=BPP/O=Example Company/CN=${DOMAIN}" -keyout certs/domain.key -x509 -days 365 -out certs/domain.crt
	sudo mkdir -p /etc/docker/certs.d/${DOMAIN}/
	sudo cp ./certs/domain.crt /etc/docker/certs.d/${DOMAIN}/
	wget -qO- http://instance-data/latest/meta-data/public-ipv4; echo

setup-gpg:
	gpg --generate-key --passphrase "coolawspassphrase" --batch <(echo "Key-Type: 1"; \
		echo "Key-Length: 4096"; \
		echo "Subkey-Type: 1"; \
		echo "Subkey-Length: 4096"; \
		echo "Expire-Date: 0"; \
		echo "Name-Real: testuser"; \
		echo "Name-Email: wkbase@gmail.com"; \
		echo "%no-protection"; )

setup-pass:
	#$(eval keyid=$(shell gpg --list-sigs | grep uid -A 1 | tail -n 1 |  awk '{print $$3}'))
	$(eval keyid=$(shell gpg --list-keys | grep pub -A 1 | tail -n 1 | awk '{print $$1}'))
	echo $(keyid)
	pass init $(keyid)
	pass rm -f docker-credential-helpers/docker-pass-initialized-check || true 
	# Give the same passphrase as above when prompted, i.e coolawspassphrase
	pass insert -f docker-credential-helpers/docker-pass-initialized-check
	docker-credential-pass list
	# pass show docker-credential-helpers/docker-pass-initialized-check

test-env:
	@echo "mkdir -p /etc/docker/certs.d/${DOMAIN}/"
	$(eval keyid=$(shell gpg --list-keys | grep pub -A 1 | tail -n 1 | awk '{print $$1}'))
	@echo "pass init ${keyid}"

