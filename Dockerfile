FROM openjdk:8
 
RUN mkdir  /csas/ &&  mkdir ~/.ssh/
RUN apt-get update && apt-get install -y git && apt-get install -y software-properties-common
RUN touch ~/.ssh/known_hosts && ssh-keyscan github.com >> ~/.ssh/known_hosts 

#install maven3
RUN mkdir -p /usr/local/apache-maven && cd /usr/local/apache-maven && wget http://apache.mirrors.lucidnetworks.net/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz &&  tar -xzvf apache-maven-3.3.9-bin.tar.gz && rm ./apache-maven-3.3.9-bin.tar.gz
ENV  M2_HOME /usr/local/apache-maven/apache-maven-3.3.9 
ENV  M2=$M2_HOME/bin 
ENV  MAVEN_OPTS="-Xms256m -Xmx512m"
ENV  PATH=$M2:$PATH


#Variant 1) for OP demo on localhost
RUN cd /csas && git clone https://github.com/mitreid-connect/OpenID-Connect-Java-Spring-Server.git 
RUN cd /csas/OpenID-Connect-Java-Spring-Server/ && mvn clean install
CMD cd /csas/OpenID-Connect-Java-Spring-Server/openid-connect-server-webapp && mvn jetty:run

#Variant 2) for RP and Enduser demo on localhost
#RUN cd /csas && git clone https://github.com/mitreid-connect/simple-web-app.git
#RUN cd /csas/simple-web-app && mvn clean install
#CMD cd /csas/simple-web-app && mvn jetty:run


#Variant 3) for development of given application. It expects volume with given webapp mounted to /csas/app/
#CMD  cd /csas/app/ && \
#     mvn clean install && \
#     cd openid-connect-server-webapp && \
#     mvn jetty:run
EXPOSE 8080 


#EXAMPLE of how to run this docker (openid_poc is name you can change): 
# Variant 1)
# Variant 2)
# Variant 3)
# build: docker build -t openid_poc .
# run:   docker run -it  -p 8080:8080 openid_poc -v -v /c:/topmonks/test/OpenID-Connect-Java-Spring-Server:/csas/app openid_poc
#
