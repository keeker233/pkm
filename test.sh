#!/bin/bash

clear

echo ' 
PKM install start
'

# Golbals
readonly MINIMUM_DISK_SIZE_GB="5"
readonly MINIMUM_MEMORY="400"
readonly PKM_path=/opt/pkm #安装路径选为opt docker挂载分区之下方便管理
readonly PKM_depens="curl smartmontools parted ntfs-3g python python3" #主要所需环境

readonly physical_memory=$(LC_ALL=C free -m | awk '/Mem:/ { print $2 }')
readonly disk_size_bytes=$(LC_ALL=C df -P / | tail -n 1 | awk '{print $4}')
readonly disk_size_gb=$((${disk_size_bytes} / 1024 / 1024))
readonly pkm_bin="pkm"
readonly pkm_tmp_folder="pkm"

port=80
install_path="/usr/local/bin"
service_path=/usr/lib/systemd/system/pkm.service
if [ ! -d "/usr/lib/systemd/system" ]; then
    service_path=/lib/systemd/system/pkm.service
    if [ ! -d "/lib/systemd/system" ]; then
        service_path=/etc/systemd/system/pkm.service
    fi
fi


show() {
    local color=("$@") output grey green red reset
    if [[ -t 0 || -t 1 ]]; then
        output='\e[0m\r\e[J' grey='\e[90m' green='\e[32m' red='\e[31m' reset='\e[0m'
    fi
    local left="${grey}[$reset" right="$grey]$reset"
    local ok="$left$green  OK  $right " failed="$left${red}FAILED$right " info="$left$green INFO $right "
    # Print color array from index $1
    Print() {
        [[ $1 == 1 ]]
        for ((i = $1; i < ${#color[@]}; i++)); do
            output+=${color[$i]}
        done
        echo -ne "$output$reset"
    }

    if (($1 == 0)); then
        output+=$ok
        color+=('\n')
        Print 1

    elif (($1 == 1)); then
        output+=$failed
        color+=('\n')
        Print 1

    elif (($1 == 2)); then
        output+=$info
        color+=('\n')
        Print 1
    fi
}

function check_port() {
    ss -tlp | grep $1\ 
}

function get_ipaddr() {
    hostname -I | awk '{print $1}'
}


#Check memory
if [[ "${physical_memory}" -lt "${MINIMUM_MEMORY}" ]]; then
    show 1 "requires atleast 1GB physical memory."
    exit 1
fi

#Check Disk
if [[ "${disk_size_gb}" -lt "${MINIMUM_DISK_SIZE_GB}" ]]; then
    show 1 "requires atleast ${MINIMUM_DISK_SIZE_GB}GB disk space (Disk space on / is ${disk_size_gb}GB)."
    exit 1
fi

#Check Docker
install_docker() {
    if [[ -x "$(command -v docker)" ]]; then  #docker 命令可执行
        show 0 "Docker already installed."  
    else
        if [[ -r /etc/os-release ]]; then 
            lsb_dist="$(. /etc/os-release && echo "$ID")"  #查看系统信息
        fi
        if [[ $lsb_dist == "openwrt" ]]; then
            show 1 "Openwrt, Please install docker manually." #openwrt 手动安装docker
            exit 1
        else
            show 0 "Docker will be installed automatically."
            curl -fsSL https://get.docker.com | bash
            if [ $? -ne 0 ]; then
                show 1 "Installation failed, please try again."
                exit 1
            else
                show 0 "Docker Successfully installed."
            fi
        fi
    fi
}

#Install Depends
install_depends() {
    ((EUID)) && sudo_cmd="sudo"
    if [[ ! -x "$(command -v '$1')" ]]; then
        show 2 "Install the necessary dependencies: $1"
        packagesNeeded=$1
        if [ -x "$(command -v apk)" ]; then
            $sudo_cmd apk add --no-cache $packagesNeeded
        elif [ -x "$(command -v apt-get)" ]; then
            $sudo_cmd apt-get -y -q install $packagesNeeded
        elif [ -x "$(command -v dnf)" ]; then
            $sudo_cmd dnf install $packagesNeeded
        elif [ -x "$(command -v zypper)" ]; then
            $sudo_cmd zypper install $packagesNeeded
        elif [ -x "$(command -v yum)" ]; then
            $sudo_cmd yum install $packagesNeeded
        elif [ -x "$(command -v pacman)" ]; then
            $sudo_cmd pacman -S $packagesNeeded
        elif [ -x "$(command -v paru)" ]; then
            $sudo_cmd paru -S $packagesNeeded
        else
            show 1 "Package manager not found. You must manually install: $packagesNeeded"
        fi
    fi
}

#Create pkm directory
create_directory() {
    ((EUID)) && sudo_cmd="sudo"
    $sudo_cmd mkdir -p $PKM_path
}


#Create Service And Start Service
gen_service() {
    ((EUID)) && sudo_cmd="sudo"
    if [ -f $service_path ]; then
        show 2 "Try stop pkm system service."
        $sudo_cmd systemctl stop pkm.service # Stop before generation
    fi
    show 2 "Create system service for pkm."
    $sudo_cmd tee $1 >/dev/null <<EOF
				[Unit]
				Description=pkm Service
				StartLimitIntervalSec=0

				[Service]
				Type=simple
				LimitNOFILE=15210
				Restart=always
				RestartSec=1
				User=root
				ExecStart=$install_path/$pkm_bin -c $PKM_path/conf/conf.ini

				[Install]
				WantedBy=multi-user.target
EOF
    show 0 "pkm service Successfully created."

    #Check Port
    if [ -n "$(check_port :http)" ]; then
        for PORT in {81..65536}; do
            if [ ! -n "$(check_port :$PORT)" ]; then
                port=$PORT
                break
            fi
        done
    fi

    #replace port
    $sudo_cmd sed -i "s/^HttpPort =.*/HttpPort = $port/g" $PKM_path/conf/conf.ini

    show 2 "Create a system startup service for pkm."

    $sudo_cmd systemctl daemon-reload
    $sudo_cmd systemctl enable pkm

    show 2 "Start pkm service."
    $sudo_cmd systemctl start pkm

    PIDS=$(ps -ef | grep pkm | grep -v grep | awk '{print $2}')
    if [[ "$PIDS" != "" ]]; then
        echo " "
        echo "==============================================================="
        echo " "
        echo "  pkm running at:"
        if [[ "$port" -eq "80" ]]; then
            echo "  http://$(get_ipaddr)"
        else
            echo "  http://$(get_ipaddr):$port"
        fi
        echo " "
        echo "  Open your browser and visit the above address."
        echo " "
        echo "==============================================================="
        echo " "
    else
        show 1 "pkm start failed."
    fi

    #$sudo_cmd systemctl status pkm
}

create_directory
install_depends "$PKM_depens"
install_docker
