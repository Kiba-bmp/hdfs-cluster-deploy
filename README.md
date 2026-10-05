# HDFS cluster Team B

Задание было развернуть HDFS из трёх DataNode, одного NameNode и одного SecondaryNameNode. Машины общие - на них уже работает кластер Team A, поэтому наш кластер полностью изолирован: свой пользователь, свои каталоги, свои порты.

## Раскладка по узлам

На team-28-nn у нас NameNode и DataNode #1. На team-28-00 идёт SecondaryNameNode и DataNode #2. На team-28-01 остаётся только DataNode #3. Репликация равна трём, так что каждый блок хранится на всех трёх узлах.

Внутренние адреса: 10.28.0.11, 10.28.0.12 и 10.28.0.13 соответственно.

Подключение двухступенчатое. С ноутбука идём на edge-узел team-28-en под пользователем team28b, и уже с него переходим внутрь по ключу team28b_internal. Логинимся всегда явно как team28b, чтобы случайно не попасть в чужую учётную запись.

## Версии

Java - Temurin OpenJDK 11.0.32.1. Hadoop - Apache Hadoop 3.4.3. Архитектура машин x86_64.

sudo у пользователя team28b нет, поэтому обе программы стоят в домашнем каталоге. Ничего системного не ставили и ни разу не вызывали sudo.

## Где всё лежит

Java в ~/apps/java, Hadoop в ~/apps/hadoop. Данные HDFS - в ~/hdfs, с подкаталогами namenode на team-28-nn, datanode на всех трёх узлах и namesecondary на team-28-00. Конфиги Hadoop лежат в ~/apps/hadoop/etc/hadoop.

## Переменные окружения

В ~/.bashrc на каждом узле прописаны JAVA_HOME, HADOOP_HOME и PATH на их bin-каталоги. Дополнительно configs/hadoop-env.sh копируется в etc/hadoop, чтобы демоны точно знали, где Java, и писали логи в ~/apps/hadoop/logs.

## core-site.xml

Файл одинаковый на всех трёх узлах. В нём одна важная настройка - fs.defaultFS указывает на наш NameNode:

fs.defaultFS = hdfs://team-28-nn:9100

Именно из неё все клиентские команды берут адрес, поэтому Team B никогда не обращается к Team A на 9000.

## hdfs-site.xml

В configs/hdfs-site.xml лежит общая часть конфига, она одинакова для всех узлов. Поверх неё на каждом узле добавляется своё значение dfs.datanode.hostname: team-28-nn, team-28-00 или team-28-01 соответственно.

Это самая важная деталь настройки. Если скопировать один и тот же конфиг на три машины, DataNode не смогут зарегистрироваться в NameNode. Скрипт deploy.sh подставляет правильное значение по имени узла автоматически, так что руками ничего править не нужно.

Пути хранения заданы явно и указывают только в наш каталог: dfs.namenode.name.dir ведёт в ~/hdfs/namenode, dfs.datanode.data.dir в ~/hdfs/datanode, dfs.namenode.checkpoint.dir в ~/hdfs/namesecondary.

## Порты

Team A занимает стандартный набор, поэтому мы взяли соседний диапазон и не пересекаемся.

NameNode RPC у нас на 9100 вместо 9000, Web UI на 9970 вместо 9870. DataNode слушает 9964 вместо 9864, 9966 вместо 9866 и 9967 вместо 9867. SecondaryNameNode - 9968 вместо 9868.

Перед первым запуском проверили на всех трёх узлах, что наши порты свободны:

ss -ltn | grep -E ":(9100|9970|9964|9966|9967|9968)\b" || true

Пустой вывод означает, что можно стартовать.

## Изоляция от Team A

Ни один файл Team A мы не трогали, ни один их процесс не останавливали. Все наши файлы лежат в /home/team28b, все порты - в диапазоне 91xx и 99xx. Ни разу не использовали killall java или pkill java, потому что на этих машинах крутятся чужие Java-процессы. Остановка делается только точечно, через hdfs --daemon stop от имени team28b.

/etc/hosts не меняли. В deploy.sh встроена проверка: если в конфиге встретится упоминание team28a, скрипт остановится и не пойдёт дальше.

## Установка

Всё ставится одним скриптом, отдельно на каждом узле:

./deploy.sh setup nn
./deploy.sh setup 00
./deploy.sh setup 01

Скрипт скачивает и распаковывает Temurin 11 и Hadoop 3.4.3, копирует конфиги, подставляет нужный dfs.datanode.hostname и создаёт каталоги ~/hdfs.

Если делать руками, точный порядок такой:

mkdir -p ~/apps && cd ~/apps
curl -L -o jdk11.tar.gz "https://api.adoptium.net/v3/binary/latest/11/ga/linux/x64/jdk/hotspot/normal/eclipse"
tar -xzf jdk11.tar.gz && mv jdk-11* java && rm jdk11.tar.gz
curl -L -o hadoop.tar.gz "https://archive.apache.org/dist/hadoop/common/hadoop-3.4.3/hadoop-3.4.3.tar.gz"
tar -xzf hadoop.tar.gz && mv hadoop-3.4.3 hadoop && rm hadoop.tar.gz
cd ~

## Форматирование NameNode

Формат выполняется один раз, только на team-28-nn и только под team28b. Повторный запуск уничтожил бы все загруженные данные, поэтому команда вынесена в отдельный подпункт и не запускается вместе с установкой:

./deploy.sh format

Скрипт откажется выполнять format, если каталог ~/hdfs/namenode/current уже существует. Перед запуском проверяются пользователь, имя узла, правильность пути dfs.namenode.name.dir и отсутствие team28a в конфигах.

## Запуск демонов

start-dfs.sh мы не использовали намеренно: он тянет за собой workers и SSH-настройки, а ручной запуск заметно проще диагностировать. Демонов поднимаем по одному, начиная с team-28-nn:

./deploy.sh start nn
./deploy.sh start 00
./deploy.sh start 01

На team-28-nn поднимаются NameNode и DataNode #1, на team-28-00 - DataNode #2 и SecondaryNameNode, на team-28-01 - DataNode #3.

Остановка - только на своём узле и только от team28b:

hdfs --daemon stop namenode
hdfs --daemon stop datanode
hdfs --daemon stop secondarynamenode

## Проверки

Готовый набор проверок вынесен в deploy.sh:

./deploy.sh verify nn

Он показывает список процессов, отчёт dfsadmin, занятые порты и количество ошибок в логах.

Ручная проверка выглядит так:

~/apps/java/bin/jps
hdfs dfsadmin -report
hdfs fsck /team28b/hdfs-test.txt -files -blocks -locations
ss -ltn | grep -E ':(9100|9970|9964|9966|9967|9968)\b'
grep -icE "error|fatal|exception" ~/apps/hadoop/logs/hadoop-team28b-*.log

## Функциональный тест

Загружали в HDFS обычный Linux-файл и читаем обратно:

echo "Hello HDFS from team28b" > ~/hdfs-test.txt
hdfs dfs -mkdir -p /team28b
hdfs dfs -put -f ~/hdfs-test.txt /team28b/
hdfs dfs -ls /team28b
hdfs dfs -cat /team28b/hdfs-test.txt

Файл создаётся на диске, потом загружается в HDFS, потом читается оттуда обратно.

## Web UI

NameNode Web UI доступен через SSH-туннель с ноутбука. Команда одинаковая на Linux и на macOS:

ssh -N -L 9970:team-28-nn:9970 team28b@2.59.83.133

Окно с этой командой оставляем работать, в браузере открываем http://localhost:9970.

Если локальный порт 9970 уже занят, можно взять другой:

ssh -N -L 19970:team-28-nn:9970 team28b@2.59.83.133

и открыть http://localhost:19970.

На 9870 заходить нельзя, это Web UI кластера Team A.
![overview](images/overview.png)
![overview](images/overview2.png)
![datanodes](images/datanodes.png)

## Логи

Логи пишутся в ~/apps/hadoop/logs. Имена файлов идут по схеме hadoop-team28b-процесс-hostname.log, то есть с нашим пользователем, а не с root. Например, hadoop-team28b-namenode-team-28-nn.log.

Строка вида RECEIVED SIGNAL 15: SIGTERM после hdfs --daemon stop считается нормой - это следствие штатной остановки процесса, а не ошибка.

## Результаты

NameNode запущен и отвечает, Live DataNode показывает3, мёртвых нод нет. Все три DataNode видны в отчёте dfsadmin, SecondaryNameNode работает на team-28-00. Репликация действительно равна трём: fsck возвращает HEALTHY и Live_repl=3, то есть блок физически лежит на трёх разных узлах, а не в трёх копиях на одном. Missing blocks, Corrupt blocks и Under-replicated blocks - все нули.

Через Web UI то же самое видно глазами: Live Nodes 3, Dead Nodes 0, Under-Replicated Blocks 0, Total Datanode Volume Failures 0. Скриншоты в evidence.

Ошибок в логах ни на одном узле нет.

Отдельно проверили, что Team A не пострадала: её порты на месте, а по её Web UI видно те же 3 живых ноды и 0 мёртвых. Метрики у чужого NameNode сняли read-only запросом к JMX, потому что dfsadmin -report по адресу 9000 требует superuser и для team28b недоступен. Снято было до начала работы и после, результат не изменился.

## Что где лежит в репозитории

configs - core-site.xml, hdfs-site.xml и hadoop-env.sh, которые скрипт копирует на узлы.

scripts - deploy.sh с подкомандами setup, format, start и verify.

evidence - все материалы проверки: отчёт dfsadmin, вывод fsck, список процессов и подсчёт ошибок в логах по каждому узлу отдельно, состояние Team A до и после работы, а также скриншоты Web UI.

## Как повторить с нуля

На каждом из трёх узлов выполняется setup с именем этого узла. Затем format на team-28-nn, один раз. Затем запуск демонов в порядке nn, 00, 01. И в конце verify на team-28-nn плюс чтение тестового файла.

./deploy.sh setup nn
./deploy.sh setup 00
./deploy.sh setup 01
./deploy.sh format
./deploy.sh start nn
./deploy.sh start 00
./deploy.sh start 01
./deploy.sh verify nn
hdfs dfs -cat /team28b/hdfs-test.txt
