# admin node
su - cephnode
ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -q

# copy rsa to all
ssh-copy-id node1
ssh-copy-id node2
ssh-copy-id node3
ssh-copy-id node4
ssh-copy-id node5
ssh node1


# all node 国内加速
cat >> ~/.bashrc <<EOF
export CEPH_DEPLOY_REPO_URL=http://mirrors.163.com/ceph/debian-jewel 
export CEPH_DEPLOY_GPG_URL=http://mirrors.163.com/ceph/keys/release.asc
EOF

# add dns
cat >> /etc/resolv.conf<<EOF
nameserver 202.96.128.166
nameserver 202.96.128.66
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
nameserver 4.4.4.4
EOF

# add cephnode user /*当然,我是用 root 来搞的*/
useradd cephnode 
echo '123' | passwd --stdin cephnode
echo "cephnode ALL = (root) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/cephnode
chmod 0440 /etc/sudoers.d/cephnode 

# install ntp server sync
yum install ntp ntpdate ntp-doc -y
crontab -e
*/1 * * * * /usr/sbin/ntpdate s2c.time.edu.cn > /dev/null 2>&1


# add 163 yum repo
echo '#...
[ceph]
name=Ceph packages for $basearch
baseurl=http://mirrors.163.com/ceph/rpm-jewel/el7/\$basearch
enabled=1
gpgcheck=0
type=rpm-md
gpgkey=https://mirrors.163.com/ceph/keys/release.asc
priority=1

[ceph-noarch]
name=Ceph noarch packages
baseurl=http://mirrors.163.com/ceph/rpm-jewel/el7/noarch
enabled=1
gpgcheck=0
type=rpm-md
gpgkey=https://mirrors.163.com/ceph/keys/release.asc
priority=1

[ceph-source]
name=Ceph source packages
baseurl=http://mirrors.163.com/ceph/rpm-jewel/el7/SRPMS
enabled=1
gpgcheck=0
type=rpm-md
gpgkey=https://mirrors.163.com/ceph/keys/release.asc
priority=1' >> /etc/yum.repos.d/ceph.repo



# node1 install ceph-deploy
yum -y install ceph-deploy


# STARTING OVER
# if at any point you run into trouble and you want to start over, execute the following to purge the Ceph packages, and erase all its data and configuration:
ceph-deploy purge {ceph-node} [{ceph-node}]
ceph-deploy purgedata {ceph-node} [{ceph-node}]
ceph-deploy forgetkeys
rm ceph.*

# As a first exercise, create a Ceph Storage Cluster with one Ceph Monitor and three Ceph OSD Daemons. Once the cluster reaches a active + clean state, expand it by adding a fourth Ceph OSD Daemon, a Metadata Server and two more Ceph Monitors. For best results, create a directory on your admin node for maintaining the configuration files and keys that ceph-deploy generates for your cluster.
# 作为第一个练习，使用一个Ceph Monitor和三个Ceph OSD守护进程创建一个Ceph存储集群。 一旦集群达到 active+clean 状态，
# 通过添加第四个Ceph OSD守护程序，元数据服务器和两个Ceph监视器来扩展集群。 
# 为获得最佳结果，请在管理节点上创建一个目录，以维护ceph-deploy为集群生成的配置文件和密钥。

# node1 作为管理节点
mkdir my-cluster
cd my-cluster

# all node 每个磁盘60G
lsblk
parted  -s  /dev/sdb  mklabel gpt
parted /dev/sdb mkpart primary ext4 0 60G

# new nodes mon
ceph-deploy new ceph1 ceph2 ceph3 

ceph-deploy install ceph1 ceph2 ceph3

ceph-deploy mon create-initial
# 在第一次清除 PurgeData 之后,发生admin_socket: exception getting command descriptions: [Errno 2] No such file or directory
rm -rf /etc/ceph/*
rm -rf /var/lib/ceph/*/*
rm -rf /var/log/ceph/*
rm -rf /var/run/ceph/*

ceph-deploy mon add ceph1 ceph2 ceph3 

ceph-deploy osd prepare ceph1:/dev/sdb1 ceph2:/dev/sdb1 ceph3:/dev/sdb1
ceph-deploy osd activate ceph1:/dev/sdb1 ceph2:/dev/sdb1 ceph3:/dev/sdb1



ceph-deploy admin ceph1 ceph2 ceph3

chmod +r /etc/ceph/ceph.client.admin.keyring

ceph health


# -------------
1/新建一个ceph pool，（两个数字为 {pg-num} [{pgp-num}）
ceph osd pool create rbdpool 100 100

2、在pool中新建一个镜像
rbd create rbdpoolimages --size 80960 -p rbdpool   
或者 
rbd create rbdpool/rbdpoolimages --size 102400
在内核为3.10的不能实现绝大部分features，使用此命令 在后边加上 --image-format 2 --image-feature  layering


3、查看相关pool以及image信息
查看池中信息
rbd ls rbdpool
查询一个池内的镜像信息
rbd --image rbdpoolimages -p rbdpool info

# 需要改 rbdimages 的权限
rbd feature disable rbdpool/rbdpoolimages exclusive-lock, object-map, fast-diff, deep-flatten


4、把镜像映射到pool块设备中，在安装了ceph以及执行过ceph-deploy admin node 命令的客户端上以root身份执行执行
rbd map rbdpoolimages -p rbdpool
# output
# /dev/rbd0

5、格式化映射的设备块

mkfs.ext4 /dev/rbd0

6、取消映射块设备、查看镜像映射map
取消映射块设备
rbd unmap /dev/rbd1
查看镜像映射map
rbd showmapped

7、扩容image
rbd resize -p rbdpool --size 150G rbdpoolimages


# other检查集群
ceph quorum_status --format json-pretty

# 密钥
grep key /etc/ceph/ceph.client.admin.keyring |awk '{printf "%s", $NF}'|base64
#example
#QVFCL1l1cGFpaExPTkJBQWxpc0dYT1podmV2U2U2T2tuSjRqb0E9PQ


# command
命令	功能
rbd create 	 创建块设备映像 
rbd ls 	 列出 rbd 存储池中的块设备 
rbd info 	 查看块设备信息 
rbd diff 	 可以统计 rbd 使用量 
rbd feature disable 	 禁止掉块设备的某些特性 
rbd map 	 映射块设备 
rbd remove 	 删除块设备 
rbd resize 	 更改块设备的大小