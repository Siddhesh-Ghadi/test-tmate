#!/bin/bash
__install_ant() {
  echo "installing ant"
  mkdir -p /opt/ant
  curl -sL https://downloads.apache.org//ant/binaries/apache-ant-1.10.11-bin.tar.gz | tar -xz --strip 1 -C /opt/ant
  echo 'export ANT_HOME=/opt/ant
  export PATH=${ANT_HOME}/bin:${PATH}' > /home/travis/.bash_profile.d/ant.bash
  chmod 644 /home/travis/.bash_profile.d/ant.bash
  chown travis: /home/travis/.bash_profile.d/ant.bash
  source /home/travis/.bash_profile.d/ant.bash
}
__install_ant
