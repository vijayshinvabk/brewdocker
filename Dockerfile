FROM ubuntu:14.04

MAINTAINER sagar.mattoo@aditi.com,vijayshinvabk@aditi.com

#######################Install##########################
RUN apt-get update -q \
    && DEBIAN_FRONTEND=noninteractive apt-get install -qy --no-install-recommends \
      ca-certificates \
      openssh-server \
      wget \
	  curl \
	  zip \
	  default-jre \ 
	  default-jdk \
	  && rm -rf /var/lib/apt/lists/*

########################GitLab##########################

# Download & Install GitLab
# If the Omnibus package version below is outdated please contribute a merge request to update it.
# If you run GitLab Enterprise Edition point it to a location where you have downloaded it.
RUN TMP_FILE=$(mktemp); \
    wget -q -O $TMP_FILE https://downloads-packages.s3.amazonaws.com/ubuntu-14.04/gitlab_7.6.2-omnibus.5.3.0.ci.1-1_amd64.deb \
    && dpkg -i $TMP_FILE \
    && rm -f $TMP_FILE

# Manage SSHD through runit
RUN mkdir -p /opt/gitlab/sv/sshd/supervise \
    && mkfifo /opt/gitlab/sv/sshd/supervise/ok \
    && printf "#!/bin/sh\nexec 2>&1\numask 077\nexec /usr/sbin/sshd -D" > /opt/gitlab/sv/sshd/run \
    && chmod a+x /opt/gitlab/sv/sshd/run \
    && ln -s /opt/gitlab/sv/sshd /opt/gitlab/service \
    && mkdir -p /var/run/sshd

# Expose web & ssh
EXPOSE 80 22

# Volume & configuration
VOLUME ["/var/opt/gitlab", "/var/log/gitlab", "/etc/gitlab"]
ADD gitlab.rb /etc/gitlab/

# Default is to run runit & reconfigure
CMD gitlab-ctl reconfigure & /opt/gitlab/embedded/bin/runsvdir-start

######################Java###############################

######################Jenkins############################

ENV JENKINS_HOME /var/jenkins_home
ENV JENKINS_HOME /var/jenkins_home

# Jenkins is ran with user `jenkins`, uid = 1000
# If you bind mount a volume from host/vloume from a data container, 
# ensure you use same uid
RUN useradd -d "$JENKINS_HOME" -u 1000 -m -s /bin/bash jenkins

# Jenkins home directoy is a volume, so configuration and build history 
# can be persisted and survive image upgrades
VOLUME /var/jenkins_home

# `/usr/share/jenkins/ref/` contains all reference configuration we want 
# to set on a fresh new installation. Use it to bundle additional plugins 
# or config file with your custom jenkins Docker image.
RUN mkdir -p /usr/share/jenkins/ref/init.groovy.d


COPY init.groovy /usr/share/jenkins/ref/init.groovy.d/tcp-slave-angent-port.groovy

ENV JENKINS_VERSION 1.596

# could use ADD but this one does not check Last-Modified header 
# see https://github.com/docker/docker/issues/8331
RUN curl -L http://mirrors.jenkins-ci.org/war/1.596/jenkins.war -o /usr/share/jenkins/jenkins.war

ENV JENKINS_UC https://updates.jenkins-ci.org
RUN chown -R jenkins "$JENKINS_HOME" /usr/share/jenkins/ref

# for main web interface:
EXPOSE 8080

# will be used by attached slave agents:
EXPOSE 50000

USER jenkins

COPY jenkins.sh /usr/local/bin/jenkins.sh
ENTRYPOINT ["/usr/local/bin/jenkins.sh"]

# from a derived Dockerfile, can use `RUN plugin.sh active.txt` to setup /usr/share/jenkins/ref/plugins from a support bundle
COPY plugins.sh /usr/local/bin/plugins.sh

##########################JIRA#################################
ENV JIRA_VERSION 6.3.1
RUN sudo mkdir -p /usr/share/jira
RUN curl -L http://www.atlassian.com/software/jira/downloads/binary/atlassian-jira-${JIRA_VERSION}.tar.gz -o /usr/share/jira/jira.tar.gz
RUN /usr/sbin/useradd --create-home --home-dir /opt/jira --groups atlassian --shell /bin/bash jira
RUN tar zxf /usr/share/jira/jira.tar.gz --strip=1 -C /opt/jira
RUN chown -R jira:jira /var/atlassian/jira
RUN echo "jira.home = /var/atlassian/jira" > /opt/jira/atlassian-jira/WEB-INF/classes/jira-application.properties
RUN chown -R jira:jira /opt/jira
RUN mv /opt/jira/conf/server.xml /opt/jira/conf/server-backup.xml

ENV CONTEXT_PATH ROOT

ADD launch.bash /launch

# Launching Jira
WORKDIR /opt/jira
VOLUME ["/var/atlassian/jira"]
EXPOSE 8090
USER jira

CMD ["/launch"]
