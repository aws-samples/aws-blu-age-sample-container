# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

FROM amazonlinux:latest

# Install packages
RUN yum upgrade -y
RUN yum install -y java-24-amazon-corretto
RUN yum install -y wget tar unzip zip

# Install AWS CLI
RUN cd /usr/share && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install

# Copy the bash wrapper script into the container
COPY wrapper.sh /usr/share/
RUN chmod 755 /usr/share/wrapper.sh

# Copy the sample java application into the container
RUN mkdir /usr/share/bluage
COPY bluAgeSample.jar /usr/share/bluage/bluAgeSample.jar

# Expose a port for the ECS Service to use
EXPOSE 3090

CMD ["/usr/share/wrapper.sh","dummyparam1","dummyparam2"]