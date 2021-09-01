#!/bin/bash
__install_ant() {
  echo "installing ant"
  curl -sL https://downloads.apache.org//ant/binaries/apache-ant-1.10.11-bin.tar.gz | tar -xz
  apache-ant-1.10.11/bin/ant
}
__install_ant
