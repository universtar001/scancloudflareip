#!/bin/bash
# asscan 获取 CF 反代节点
clear
if [[ -f /etc/redhat-release ]]; then
    systemcommand="yum"
elif cat /etc/issue | grep -Eqi "debian"; then
    systemcommand="apt"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    systemcommand="apt"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    systemcommand="yum"
elif cat /proc/version | grep -Eqi "debian"; then
    systemcommand="apt"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    systemcommand="apt"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    systemcommand="yum"
else
    echo -e "错误: 未检测到系统版本\n" && exit 1
fi
if [ `id -u` != 0 ];then
    echo -e "错误: 仅限 root 用户执行"
fi
function installmasscan() {
if [ $systemcommand = "apt" ];then
    sudo apt upgrade
    sudo apt update
    apt install curl clang gcc make libpcap-dev masscan -y
else
    sudo yum install upgrade
    yum install curl git clang gcc gcc-c++ flex bison make libpcap-dev -y
    git clone https://github.com/robertdavidgraham/masscan
    cd masscan
    make
    make install
    cd ~/
fi
clear
echo "已安装masscan"
echo "有一切问题请手动安装！"
echo "有一切问题请手动安装！"
echo "有一切问题请手动安装！"
}
if ! [ -x "$(command -v masscan)" ]; then
  echo '检测到masscan未安装'
  echo '安装中..'
  installmasscan
fi

echo "本脚需要用root权限执行masscan扫描"
echo "请自行确认当前是否以root权限运行"
echo "1.单个AS模式"
echo "2.批量AS列表模式"
echo "3.从url获取AS列表模式"
read -p "请输入模式号(默认模式1):" scanmode
if [ -z "$scanmode" ]
then
    scanmode=1
fi
if [ $scanmode == 1 ]
then
    clear
    echo "当前为单个AS模式"
    read -p "请输入AS号码(默认45102):" asn
    read -p "请输入扫描端口(默认443):" port
    if [ -z "$asn" ]
    then
        asn=45102
    fi
    if [ -z "$port" ]
    then
        port=443
    fi
elif [ $scanmode == 2 ]
then
    clear
    echo "当前为批量AS列表模式"
    echo "待扫描的默认列表文件as.txt格式如下所示"
    echo -e "\n45102:443\n132203:443\n自治域号:端口号\n"
    read -p "请设置列表文件(默认as.txt):" filename
    if [ -z "$filename" ];then
        filename=as.txt
    else
        echo "文件不存在"
        exit
    fi
elif [ $scanmode == 3 ]
then
    clear
    echo "当前为从url获取AS列表模式"
    read -p "请输入AS列表url" url
    code=`curl -L -o /dev/null -s -w %{http_code} $url`
    if [ "$url" -ne "200" ];then
        echo "获取失败 网络连接有误"
        exit
    fi
else
    echo "输入的数值不正确,脚本已退出!"
    exit
fi
read -p "请设置masscan pps rate(默认10000):" rate
read -p "请设置curl测试进程数(默认50,最大100):" tasknum
read -p "是否需要测速[(默认0.否)1.是]:" mode
if [ -z "$rate" ]
then
    rate=10000
fi
if [ -z "$tasknum" ]
then
    tasknum=50
fi
if [ $tasknum -eq 0 ]
then
    echo "进程数不能为0,自动设置为默认值"
    tasknum=50
fi
if [ $tasknum -gt 100 ]
then
    echo "超过最大进程限制,自动设置为最大值"
    tasknum=100
fi
if [ -z "$mode" ]
then
    mode=0
fi

function divsubnet(){
mask=$5;a=$1;b=$2;c=$3;d=$4;
echo "拆分子网:$a.$b.$c.$d/$mask";

if [ $mask -ge 8 ] && [ $mask -le 23 ];then
    ipstart=$(((a<<24)|(b<<16)|(c<<8)|l));
    hostend=$((2**(32-mask)-1));
    loop=0;
    while [ $loop -le $hostend ]
    do
        subnet=$((ipstart|loop));
        a=$(((subnet>>24)&255));
        b=$(((subnet>>16)&255));
        c=$(((subnet>>8)&255));
        d=$(((subnet>>0)&255));
        loop=$((loop+256));
        echo $a.$b.$c.$d/24 >> ips.txt;
    done
else
    echo $a.$b.$c.$d/24 >> ips.txt;
fi
}

function getip(){
rm -rf ips.txt
for i in `cat asn/$asn`
do
    a=$(echo $i | awk -F. '{print $1}');
    b=$(echo $i | awk -F. '{print $2}');
    c=$(echo $i | awk -F. '{print $3}');
    d=$(echo $i | awk -F. '{print $4}' | awk -F/ '{print $1}');
    mask=$(echo $i | awk -F/ '{print $2}');
    divsubnet $a $b $c $d $mask
done
sort -u ips.txt | sed -e 's/\./#/g' | sort -t# -k 1n -k 2n -k 3n -k 4n | sed -e 's/#/\./g'>asn/$asn-24
rm -rf ips.txt
}

function colocation(){
curl --ipv4 --retry 3 -s https://speed.cloudflare.com/locations | sed -e 's/},{/\n/g' -e 's/\[{//g' -e 's/}]//g' -e 's/"//g' -e 's/,/:/g' | awk -F: '{print $12","$10"-("$2")"}'>colo.txt
}

function realip(){
sparrow=$(curl --resolve sparrow.cloudflare.com:$port:$1 https://sparrow.cloudflare.com:$port/ -s --connect-timeout 1 --max-time 2)
if [ "$sparrow" == "Unauthorized" ]
then
    echo $1 >> realip.txt
fi
}

function rtt(){
declare -i ms
ip=$i
curl -A "trace" --retry 2 --resolve www.cloudflare.com:$port:$ip https://www.cloudflare.com:$port/cdn-cgi/trace -s --connect-timeout 2 --max-time 3 -w "timems="%{time_connect}"\n" >> log/$1
status=$(grep uag=trace log/$1 | wc -l)
if [ $status == 1 ]
then
    clientip=$(grep ip= log/$1 | cut -f 2- -d'=')
    colo=$(grep colo= log/$1 | cut -f 2- -d'=')
    location=$(grep $colo colo.txt | awk -F"-" '{print $1}' | awk -F"," '{print $1}')
    country=$(grep loc= log/$1 | cut -f 2- -d'=')
    ms=$(grep timems= log/$1 | awk -F"=" '{printf ("%d\n",$2*1000)}')
    if [[ "$clientip" == "$publicip" ]]
    then
        clientip=0.0.0.0
        ipstatus=官方
    elif [[ "$clientip" == "$ip" ]]
    then
        ipstatus=中转
    else
        ipstatus=隧道
    fi
    rm -rf log/$1
    echo "$ip,$port,$clientip,$country,$location,$ipstatus,$ms ms" >> rtt.txt
else
