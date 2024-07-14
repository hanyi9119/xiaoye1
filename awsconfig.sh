#!/bin/bash

# ����Ƿ��ṩ���㹻�Ĳ���
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <interface_name> <traffic_limit>"
    exit 1
fi

# ����
interface_name=$1
traffic_limit=$2

# ���°��б���װcron����
sudo apt update
sudo apt install cron -y

# ��װ����
sudo apt install vnstat bc -y

# ����vnstat
sudo sed -i '0,/^;Interface ""/s//Interface '\"$interface_name\"'/' /etc/vnstat.conf
sudo sed -i "0,/^;UnitMode.*/s//UnitMode 1/" /etc/vnstat.conf
sudo sed -i "0,/^;MonthRotate.*/s//MonthRotate 1/" /etc/vnstat.conf

# ���ò�����vnstat����
sudo systemctl enable vnstat
sudo systemctl restart vnstat

# �����Զ��ػ��ű�check.sh
cat << EOF | sudo tee /root/check.sh > /dev/null
#!/bin/bash

# ��������
interface_name="$interface_name"
# ������ֵ���ޣ���GBΪ��λ��
traffic_limit=$traffic_limit

# ����������¼
vnstat -i "$interface_name"

# ��ȡÿ��������\$11: ��վ+��վ����; \$10: ��վ����; \$9: ��վ����
TRAFF_USED=\$(vnstat --oneline b | awk -F';' '{print \$11}')

# ����Ƿ��ȡ������
if [[ -z "\$TRAFF_USED" ]]; then
    echo "Error: Not enough data available yet."
    exit 1
fi

# ������ת��ΪGB
CHANGE_TO_GB=\$(echo "scale=2; \$TRAFF_USED / 1073741824" | bc)

# ���ת����������Ƿ�Ϊ��Ч����
if ! [[ "\$CHANGE_TO_GB" =~ ^[0-9]+([.][0-9]+)?\$ ]]; then
    echo "Error: Invalid traffic data."
    exit 1
fi

# �Ƚ������Ƿ񳬹���ֵ
if (( \$(echo "\$CHANGE_TO_GB > \$traffic_limit" | bc -l) )); then
    sudo /usr/sbin/shutdown -h now
fi
EOF

# ����Ȩ��
sudo chmod +x /root/check.sh

# ���ö�ʱ����ÿ3����ִ��һ�μ��
(crontab -l ; echo "*/3 * * * * /bin/bash /root/check.sh > /root/shutdown_debug.log 2>&1") | crontab -

echo "�󹦸�ɣ��ű��Ѱ�װ��������ɡ�"
