#!/usr/bin/env bash
set -euo pipefail

HADOOP_VER="3.4.3"
JAVA_URL="https://api.adoptium.net/v3/binary/latest/11/ga/linux/x64/jdk/hotspot/normal/eclipse"
HADOOP_URL="https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VER}/hadoop-${HADOOP_VER}.tar.gz"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

guard() {
  local expect="$1"
  local host; host="$(hostname)"
  if [ "$(whoami)" != "team28b" ]; then
    echo "СТОП: нужно работать под team28b, а не под $(whoami)"; exit 1
  fi
  if [ "$host" != "$expect" ]; then
    echo "СТОП: команда для $expect, а вы на $host"; exit 1
  fi
  echo "OK: user=$(whoami) host=$host"
}

node_dirs() {
  case "$1" in
    nn) mkdir -p "$HOME/hdfs/namenode" "$HOME/hdfs/datanode" ;;
    00) mkdir -p "$HOME/hdfs/namesecondary" "$HOME/hdfs/datanode" ;;
    01) mkdir -p "$HOME/hdfs/datanode" ;;
    *)  echo "СТОП: узел должен быть nn, 00 или 01"; exit 1 ;;
  esac
}

write_hdfs_site() {
  cp "$REPO/configs/hdfs-site.xml" "$HADOOP_HOME/etc/hadoop/hdfs-site.xml"
  sed -i '$i\
    <property>\
        <name>dfs.datanode.hostname</name>\
        <value>'"$1"'</value>\
    </property>' "$HADOOP_HOME/etc/hadoop/hdfs-site.xml"
  if grep -q team28a "$HADOOP_HOME/etc/hadoop/hdfs-site.xml"; then
    echo "СТОП: в конфиге найдено team28a"; exit 1
  fi
}

setup() {
  guard "$1"
  export JAVA_HOME="$HOME/apps/java"
  export HADOOP_HOME="$HOME/apps/hadoop"

  mkdir -p "$HOME/apps"
  if [ ! -x "$JAVA_HOME/bin/java" ]; then
    echo "--- ставим Temurin OpenJDK 11"
    cd "$HOME/apps"
    curl -L -o jdk11.tar.gz "$JAVA_URL"
    tar -xzf jdk11.tar.gz
    mv jdk-11* java
    rm -f jdk11.tar.gz
  fi

  if [ ! -x "$HADOOP_HOME/bin/hdfs" ]; then
    echo "--- ставим Hadoop $HADOOP_VER"
    cd "$HOME/apps"
    curl -L -o hadoop.tar.gz "$HADOOP_URL"
    tar -xzf hadoop.tar.gz
    mv "hadoop-$HADOOP_VER" hadoop
    rm -f hadoop.tar.gz
  fi

  cp "$REPO/configs/hadoop-env.sh" "$HADOOP_HOME/etc/hadoop/hadoop-env.sh"

  if ! grep -q "HADOOP_HOME=\$HOME/apps/hadoop" "$HOME/.bashrc"; then
    cat >> "$HOME/.bashrc" << 'BRC'
export JAVA_HOME=$HOME/apps/java
export HADOOP_HOME=$HOME/apps/hadoop
export PATH=$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH
BRC
  fi

  cp "$REPO/configs/core-site.xml" "$HADOOP_HOME/etc/hadoop/core-site.xml"
  write_hdfs_site "$1"
  node_dirs "$1"

  export PATH="$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH"
  echo "--- версии"
  java -version
  hadoop version
  echo "--- готово на узле $1"
}

format() {
  guard team-28-nn
  export JAVA_HOME="$HOME/apps/java"
  export HADOOP_HOME="$HOME/apps/hadoop"
  export PATH="$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH"
  if [ -d "$HOME/hdfs/namenode/current" ]; then
    echo "СТОП: $HOME/hdfs/namenode/current уже существует."
    echo "      NameNode уже форматировался. Повторный format сотрёт данные."
    exit 1
  fi
  echo "--- форматирование NameNode (только на team-28-nn)"
  hdfs namenode -format
  echo "--- format выполнен. Повторно НЕ запускать."
}

start() {
  guard "$1"
  export JAVA_HOME="$HOME/apps/java"
  export HADOOP_HOME="$HOME/apps/hadoop"
  export PATH="$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH"
  case "$1" in
    nn) hdfs --daemon start namenode; hdfs --daemon start datanode ;;
    00) hdfs --daemon start datanode; hdfs --daemon start secondarynamenode ;;
    01) hdfs --daemon start datanode ;;
  esac
  sleep 3
  "$JAVA_HOME/bin/jps"
}

verify() {
  guard "$1"
  export JAVA_HOME="$HOME/apps/java"
  export HADOOP_HOME="$HOME/apps/hadoop"
  export PATH="$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH"
  echo "=== jps ==="
  "$JAVA_HOME/bin/jps"
  echo "=== report ==="
  hdfs dfsadmin -report
  echo "=== порты ==="
  ss -ltn | grep -E ':(9100|9970|9964|9966|9967|9968)\b' || true
  echo "=== ошибки в логах ==="
  grep -icE "error|fatal|exception" "$HADOOP_HOME"/logs/hadoop-team28b-*.log || true
}

case "${1:-}" in
  setup)  setup  "${2:-}" ;;
  format) format ;;
  start)  start  "${2:-}" ;;
  verify) verify "${2:-}" ;;
  *)
    echo "Использование:"
    echo "  ./deploy.sh setup <nn|00|01>   # Java, Hadoop, конфиги, каталоги"
    echo "  ./deploy.sh format # ТОЛЬКО на nn, один раз, сотрёт данные"
    echo "  ./deploy.sh start  <nn|00|01>  # запуск демонов узла"
    echo "  ./deploy.sh verify <nn|00|01>  # read-only проверки"
    exit 1 ;;
esac
