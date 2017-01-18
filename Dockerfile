FROM openjdk:8-jre

ENV CATALINA_HOME /usr/local/tomcat
ENV PATH $CATALINA_HOME/bin:$PATH
RUN mkdir -p "$CATALINA_HOME"
WORKDIR $CATALINA_HOME

# let "Tomcat Native" live somewhere isolated
ENV TOMCAT_NATIVE_LIBDIR $CATALINA_HOME/native-jni-lib
ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$TOMCAT_NATIVE_LIBDIR

# runtime dependencies for Tomcat Native Libraries
# Tomcat Native 1.2+ requires a newer version of OpenSSL than debian:jessie has available (1.0.2g+)
# see http://tomcat.10.x6.nabble.com/VOTE-Release-Apache-Tomcat-8-0-32-tp5046007p5046024.html (and following discussion)
ENV OPENSSL_VERSION 1.1.0c-2
RUN { \
		echo 'deb http://deb.debian.org/debian stretch main'; \
	} > /etc/apt/sources.list.d/stretch.list \
	&& { \
# add a negative "Pin-Priority" so that we never ever get packages from stretch unless we explicitly request them
		echo 'Package: *'; \
		echo 'Pin: release n=stretch'; \
		echo 'Pin-Priority: -10'; \
		echo; \
# except OpenSSL, which is the reason we're here
		echo 'Package: openssl libssl*'; \
		echo "Pin: version $OPENSSL_VERSION"; \
		echo 'Pin-Priority: 990'; \
	} > /etc/apt/preferences.d/stretch-openssl
RUN apt-get update && apt-get install -y --no-install-recommends \
		libapr1 \
		openssl="$OPENSSL_VERSION" \
	&& rm -rf /var/lib/apt/lists/*

# see https://www.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/KEYS
# see also "update.sh" (https://github.com/docker-library/tomcat/blob/master/update.sh)
ENV GPG_KEYS 05AB33110949707C93A279E3D3EFE6B686867BA6 07E48665A34DCAFAE522E5E6266191C37C037D42 47309207D818FFD8DCD3F83F1931D684307A10A5 541FBE7D8F78B25E055DDEE13C370389288584E7 61B832AC2F1C5A90F0F9B00A1C506407564C17A3 713DA88BE50911535FE716F5208B0AB1D63011C7 79F7026C690BAA50B92CD8B66A3AD3F4F22C4FED 9BA44C2621385CB966EBA586F72C284D731FABEE A27677289986DB50844682F8ACB77FC2E86E29AC A9C5DF4D22E99998D9875A5110C01C5A2F6059E7 DCFD35E0BF8CA7344752DE8B6FB21E8933C60243 F3A04C595DB5B6A5F1ECA43E3B7BBB100D811BBE F7DA48BB64BCB84ECBA7EE6935CD23C10D498E23
RUN curl https://apt.dockerproject.org/gpg > docker.gpg.key && echo "c836dc13577c6f7c133ad1db1a2ee5f41ad742d11e4ac860d8e658b2b39e6ac1 docker.gpg.key" | sha256sum -c && apt-key add docker.gpg.key && rm docker.gpg.key
#RUN set -ex; \
#	for key in $GPG_KEYS; do \
#		gpg --keyserver hkps.pool.sks-keyservers.net --recv-keys "$key"; \
#	done

ENV TOMCAT_MAJOR 8
ENV TOMCAT_VERSION 8.0.39

# https://issues.apache.org/jira/browse/INFRA-8753?focusedCommentId=14735394#comment-14735394
ENV TOMCAT_TGZ_URL https://www.apache.org/dyn/closer.cgi?action=download&filename=tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz
# not all the mirrors actually carry the .asc files :'(
ENV TOMCAT_ASC_URL https://www.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.asc

RUN set -x \
	\
	&& wget -O tomcat.tar.gz "$TOMCAT_TGZ_URL" \
	&& wget -O tomcat.tar.gz.asc "$TOMCAT_ASC_URL" \
#	&& gpg --batch --verify tomcat.tar.gz.asc tomcat.tar.gz \
	&& tar -xvf tomcat.tar.gz --strip-components=1 \
	&& rm bin/*.bat \
	&& rm tomcat.tar.gz* \
	\
	&& nativeBuildDir="$(mktemp -d)" \
	&& tar -xvf bin/tomcat-native.tar.gz -C "$nativeBuildDir" --strip-components=1 \
	&& nativeBuildDeps=" \
		gcc \
		libapr1-dev \
		libssl-dev \
		make \
		openjdk-${JAVA_VERSION%%[-~bu]*}-jdk=$JAVA_DEBIAN_VERSION \
	" \
	&& apt-get update && apt-get install -y --no-install-recommends $nativeBuildDeps && rm -rf /var/lib/apt/lists/* \
	&& ( \
		export CATALINA_HOME="$PWD" \
		&& cd "$nativeBuildDir/native" \
		&& ./configure \
			--libdir="$TOMCAT_NATIVE_LIBDIR" \
			--prefix="$CATALINA_HOME" \
			--with-apr="$(which apr-1-config)" \
			--with-java-home="$(docker-java-home)" \
			--with-ssl=yes \
		&& make -j$(nproc) \
		&& make install \
	) \
	&& apt-get purge -y --auto-remove $nativeBuildDeps \
	&& rm -rf "$nativeBuildDir" \
	&& rm bin/tomcat-native.tar.gz

# verify Tomcat Native is working properly
RUN set -e \
	&& nativeLines="$(catalina.sh configtest 2>&1)" \
	&& nativeLines="$(echo "$nativeLines" | grep 'Apache Tomcat Native')" \
	&& nativeLines="$(echo "$nativeLines" | sort -u)" \
	&& if ! echo "$nativeLines" | grep 'INFO: Loaded APR based Apache Tomcat Native library' >&2; then \
		echo >&2 "$nativeLines"; \
		exit 1; \
	fi

RUN sed -i "s|</tomcat-users>|<user username=\"tomcat\" password=\"tomcat\" roles=\"tomcat,manager-gui\"/></tomcat-users>|g" /usr/local/tomcat/conf/tomcat-users.xml
# getting apps
RUN mkdir  /topmonks/ &&  mkdir ~/.ssh/
RUN apt-get update && apt-get install -y git && apt-get install -y maven
RUN touch ~/.ssh/known_hosts && ssh-keyscan github.com >> ~/.ssh/known_hosts 
#RUN cd /topmonks && git clone https://github.com/hlisnikovsky/mitre-server.git
#RUN cd /topmonks/mitre-server/OpenID-Connect-Java-Spring-Server/

RUN apt-get install -y software-properties-common
# Install Oracle Java 8
RUN apt-get install -y aptitude
RUN aptitude install -y python-software-properties
RUN echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" | tee -a /etc/apt/sources.list.d/webupd8team-java.list
RUN echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" | tee -a /etc/apt/sources.list.d/webupd8team-java.list
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886
RUN aptitude update
# Enable silent install
RUN echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections
RUN RUN RUN echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections
RUN aptitude -y install oracle-java8-installer
RUN update-java-alternatives -s java-8-oracle
RUN apt-get install -y oracle-java8-set-default

ENV JAVA_HOME=/usr/lib/jvm/java-8-oracle/jre/
ENV JAVA_VERSION=1.8.0_111

#install maven3
RUN mkdir -p /usr/local/apache-maven && cd /usr/local/apache-maven && wget http://apache.mirrors.lucidnetworks.net/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz &&  tar -xzvf apache-maven-3.3.9-bin.tar.gz && rm ./apache-maven-3.3.9-bin.tar.gz
ENV  M2_HOME /usr/local/apache-maven/apache-maven-3.3.9 
ENV  M2=$M2_HOME/bin 
ENV  MAVEN_OPTS="-Xms256m -Xmx512m"
ENV  PATH=$M2:$PATH


# Add the PostgreSQL PGP key to verify their Debian packages.
# It should be the same key as https://www.postgresql.org/media/keys/ACCC4CF8.asc
RUN apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8

# Add PostgreSQL's repository. It contains the most recent stable release
#     of PostgreSQL, ``9.3``.
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ precise-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Install ``python-software-properties``, ``software-properties-common`` and PostgreSQL 9.3
#  There are some warnings (in red) that show up during the build. You can hide
#  them by prefixing each apt-get statement with DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y python-software-properties software-properties-common postgresql-9.3 postgresql-client-9.3 postgresql-contrib-9.3

ENV POSTGRES_PASSWORD=postgres
# Note: The official Debian and Ubuntu images automatically ``apt-get clean``
# after each ``apt-get``

# Run the rest of the commands as the ``postgres`` user created by the ``postgres-9.3`` package when it was ``apt-get installed``
USER postgres

# Create a PostgreSQL role named ``docker`` with ``docker`` as the password and
# then create a database `docker` owned by the ``docker`` role.
# Note: here we use ``&&\`` to run commands one after the other - the ``\``
#       allows the RUN command to span multiple lines.
RUN    /etc/init.d/postgresql start &&\
    psql --command "CREATE USER oic WITH SUPERUSER PASSWORD 'oic';" &&\
    createdb -O oic oic

# Adjust PostgreSQL configuration so that remote connections to the
# database are possible.
RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/9.3/main/pg_hba.conf

# And add ``listen_addresses`` to ``/etc/postgresql/9.3/main/postgresql.conf``
RUN echo "listen_addresses='*'" >> /etc/postgresql/9.3/main/postgresql.conf

# Expose the PostgreSQL port
EXPOSE 5432

# Add VOLUMEs to allow backup of config, logs and databases
VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]

#invalidate cache - always pull most recent git data
ARG CACHE_DATE=2016-01-06
USER root
#getting app
RUN pwd
RUN cd /topmonks && git clone https://github.com/hlisnikovsky/mitre-server.git
USER postgres
RUN /etc/init.d/postgresql start && \
    psql -f /topmonks/mitre-server/OpenID-Connect-Java-Spring-Server/openid-connect-server-webapp/src/main/resources/db/psql/psql_database_tables.sql && \
    psql -f /topmonks/mitre-server/OpenID-Connect-Java-Spring-Server/openid-connect-server-webapp/src/main/resources/db/psql/security-schema.sql && \
    psql -f /topmonks/mitre-server/OpenID-Connect-Java-Spring-Server/openid-connect-server-webapp/src/main/resources/db/psql/scopes.sql && \
    psql -f /topmonks/mitre-server/OpenID-Connect-Java-Spring-Server/openid-connect-server-webapp/src/main/resources/db/psql/clients.sql && \
    psql -f /topmonks/mitre-server/OpenID-Connect-Java-Spring-Server/openid-connect-server-webapp/src/main/resources/db/psql/users.sql

USER root
RUN cd /topmonks/mitre-server/OpenID-Connect-Java-Spring-Server/ && mvn clean install
RUN cd /topmonks/csas/mitre-server/simple-web-app/ && mvn clean install
RUN cp -dpR /topmonks/mitre-server/OpenID-Connect-Java-Spring-Server/openid-connect-server-webapp/target/openid-connect-server-webapp.war /usr/local/tomcat/webapps/
RUN cp -dpR /topmonks/mitre-server/OpenID-Connect-Java-Spring-Server/uma-server-webapp/target/uma-server-webapp.war /usr/local/tomcat/webapps/
RUN cp -dpR /topmonks/mitre-server/simple-web-app/target/simple-web-app.war /usr/local/tomcat/webapps/
EXPOSE 8080 5432
CMD /etc/init.d/postgresql start && /usr/local/tomcat/bin/catalina.sh  run
# Set the default command to run when starting the container
#CMD ["/usr/lib/postgresql/9.3/bin/postgres", "-D", "/var/lib/postgresql/9.3/main", "-c", "config_file=/etc/postgresql/9.3/main/postgresql.conf"]
