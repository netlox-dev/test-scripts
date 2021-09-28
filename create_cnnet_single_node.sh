#!/bin/bash
# This script creates a set of host containers and sets up network connectivity between 
# them using another container "loxilight" which acts as the communication hub. 
# This script is used as a means to emulate a kubernetes or cloud-native network and 
# explore how loxilight eBPF can be used to enhance performance of linux kernel 
# networking many folds.
# Copyright (C) 2021,  NetLOX, www.netlox.io

## Create various network containers
sudo ip netns add loxilight
sudo ip netns add l3h1
sudo ip netns add l3h2
sudo ip netns add l2h1
sudo ip netns add l2h2
sudo ip netns add l2vxh1
sudo ip netns add l2vxh2
sudo ip netns add l3vxh1
sudo ip netns add l3vxh2

## Disable ipv6 for now
sudo ip netns exec loxilight sysctl net.ipv6.conf.all.disable_ipv6=1

## Create two hosts l3h1 and l3h2 which communicate with L3 routing over loxilight namespace
sudo ip -n loxilight link add hs1 type veth peer name eth0 netns l3h1
sudo ip -n loxilight link set hs1 up
sudo ip -n l3h1 link set eth0 up
sudo ip netns exec loxilight ifconfig hs1 31.31.31.254/24 up
sudo ip netns exec l3h1 ifconfig eth0 31.31.31.1/24 up
sudo ip netns exec l3h1 ip route add default via 31.31.31.254

sudo ip -n loxilight link add hs2 type veth peer name eth0 netns l3h2
sudo ip -n loxilight link set hs2 up
sudo ip -n l3h2 link set eth0 up
sudo ip netns exec loxilight ifconfig hs2 32.32.32.254/24 up
sudo ip netns exec l3h2 ifconfig eth0 32.32.32.1/24 up
sudo ip netns exec l3h2 ip route add default via 32.32.32.254

## Create two hosts l2h1 and l2h2 which communicate with L2 bridging over loxilight namespace
sudo ip -n loxilight link add hs3 type veth peer name eth0 netns l2h1
sudo ip -n loxilight link set hs3 up
sudo ip -n l2h1 link set eth0 up
sudo ip netns exec l2h1 vconfig add eth0 100
sudo ip netns exec l2h1 ifconfig eth0.100 100.100.100.1/24 up
sudo ip netns exec l2h1 ip route add default via 100.100.100.254

sudo ip -n loxilight link add hs4 type veth peer name eth0 netns l2h2
sudo ip -n loxilight link set hs4 up
## Setup related configuration in loxilight
sudo ip netns exec loxilight ifconfig hs7 17.17.17.254/24 up
sudo ip -n loxilight link add hs8 type veth peer name eth0 netns l3vxh2
sudo ip -n loxilight link set hs8 up
sudo ip -n l3vxh2 link set eth0 up
sudo ip netns exec loxilight brctl addbr hsvlan8
sudo ip netns exec loxilight brctl addif hsvlan8 hs8
sudo ip netns exec loxilight ip link set hsvlan8 up
sudo ip netns exec loxilight ip addr add 8.8.8.254/24 dev hsvlan8
sudo ip netns exec loxilight ip link add hsvxlan78 type vxlan id 78 local 8.8.8.254 dev hsvlan8 dstport 4789
sudo ip netns exec loxilight ip link set hsvxlan78 up
sudo ip netns exec loxilight ifconfig hsvxlan78 78.78.78.254/24 up
sudo ip netns exec loxilight bridge fdb append 00:00:00:00:00:00 dst 8.8.8.1 dev hsvxlan78

## Setup l3vxh2
sudo ip netns exec l3vxh2 ifconfig eth0 8.8.8.1/24 up
sudo ip netns exec l3vxh2 ip link add vxlan78 type vxlan id 78 local 8.8.8.1 dev eth0 dstport 4789
sudo ip netns exec l3vxh2 ifconfig vxlan78 78.78.78.1/24 up
sudo ip netns exec l3vxh2 ip addr add 18.18.18.1/24 dev vxlan78
sudo ip netns exec l3vxh2  bridge fdb append 00:00:00:00:00:00 dst 8.8.8.254 dev vxlan78
sudo ip netns exec l3vxh2 ip route add default via 78.78.78.254
sudo ip netns exec loxilight ip route add 18.18.18.0/24 via 78.78.78.1

## Setup eBPF pin directory path
sudo mkdir -p /opt/netlox/loxilight/
sudo mount -t bpf bpf /opt/netlox/loxilight/

sudo ip -n l2h2 link set eth0 up
sudo ip netns exec l2h2 vconfig add eth0 100
udo ip netns exec l2h2 ifconfig eth0.100 100.100.100.2/24 up
sudo ip netns exec l2h2 ip route add default via 100.100.100.254

sudo ip netns exec loxilight brctl addbr hsvlan100
sudo ip netns exec loxilight vconfig add hs3 100
sudo ip netns exec loxilight vconfig add hs4 100
sudo ip netns exec loxilight brctl addif hsvlan100 hs3.100
sudo ip netns exec loxilight brctl addif hsvlan100 hs4.100
sudo ip netns exec loxilight ifconfig hs3.100 up
sudo ip netns exec loxilight ifconfig hs4.100 up
sudo ip netns exec loxilight ifconfig hsvlan100 100.100.100.254/24 up

## Create two hosts l2vxh1 and l2vxh2 which communicate using vxlan underlay over loxilight
## We call them l2 because their attachment point to vxlan is of type l2(or vlan). In otherwords,
## this resembles vlan to vxlan translation. 
sudo ip -n loxilight link add hs5 type veth peer name eth0 netns l2vxh1
sudo ip -n loxilight link set hs5 up
sudo ip -n l2vxh1 link set eth0 up
sudo ip netns exec l2vxh1 ifconfig eth0 50.50.50.1/24 up

sudo ip -n loxilight link add hs6 type veth peer name eth0 netns l2vxh2
sudo ip -n loxilight link set hs6 up
sudo ip -n l2vxh2 link set eth0 up
sudo ip netns exec l2vxh2 ifconfig eth0 2.2.2.2/24 up
sudo ip netns exec l2vxh2 ip link add vxlan50 type vxlan id 50 local 2.2.2.2 dev eth0 dstport 4789
sudo ip netns exec l2vxh2 ifconfig vxlan50 50.50.50.2/24 up
sudo ip netns exec l2vxh2 bridge fdb append 00:00:00:00:00:00 dst 2.2.2.1 dev vxlan50

sudo ip netns exec loxilight brctl addbr hsvlan20
sudo ip netns exec loxilight brctl addif hsvlan20 hs6
sudo ip netns exec loxilight ip link set hsvlan20 up
sudo ip netns exec loxilight ip addr add 2.2.2.1/24 dev hsvlan20
sudo ip netns exec loxilight ip link add hsvxlan50 type vxlan id 50 local 2.2.2.1 dev hsvlan20 dstport 4789
sudo ip netns exec loxilight ip link set hsvxlan50 up
sudo ip netns exec loxilight bridge fdb append 00:00:00:00:00:00 dst 2.2.2.2 dev hsvxlan50
sudo ip netns exec loxilight brctl addbr hsvlan50
sudo ip netns exec loxilight brctl addif hsvlan50 hsvxlan50
sudo ip netns exec loxilight brctl addif hsvlan50 hs5
sudo ip netns exec loxilight ip link set hsvlan50 up


## Setup vxlan access port as trunk in l2vxh1 and also corresponding underlay interface of hsvxlan51 as trunk
## Setup l2vxh1
sudo ip netns exec l2vxh1 vconfig add eth0 51
sudo ip netns exec l2vxh1 ifconfig eth0.51 51.51.51.1/24 up

## Setup l2vxh2
sudo ip netns exec l2vxh2 vconfig add eth0 30
sudo ip netns exec l2vxh2 ifconfig eth0.30 3.3.3.2/24 up
sudo ip netns exec l2vxh2 ip link add vxlan51 type vxlan id 51 local 3.3.3.2 dev eth0.30 dstport 4789
sudo ip netns exec l2vxh2 ifconfig vxlan51 51.51.51.2/24 up
sudo ip netns exec l2vxh2  bridge fdb append 00:00:00:00:00:00 dst 3.3.3.1 dev vxlan51

## Setup loxilight hsvxlan51
sudo ip netns exec loxilight brctl addbr hsvlan30
sudo ip netns exec loxilight vconfig add hs6 30
sudo ip netns exec loxilight ip link set hs6.30 up
sudo ip netns exec loxilight brctl addif hsvlan30 hs6.30
sudo ip netns exec loxilight ip link set hsvlan30 up
sudo ip netns exec loxilight ip addr add 3.3.3.1/24 dev hsvlan30
sudo ip netns exec loxilight ip link add hsvxlan51 type vxlan id 51 local 3.3.3.1 dev hsvlan30 dstport 4789
sudo ip netns exec loxilight ip link set hsvxlan51 up
sudo ip netns exec loxilight bridge fdb append 00:00:00:00:00:00 dst 3.3.3.2 dev hsvxlan51
sudo ip netns exec loxilight brctl addbr hsvlan51
sudo ip netns exec loxilight vconfig add hs5 51
sudo ip netns exec loxilight ip link set hs5.51 up
sudo ip netns exec loxilight brctl addif hsvlan51 hsvxlan51
sudo ip netns exec loxilight brctl addif hsvlan51 hs5.51
sudo ip netns exec loxilight ip link set hsvlan51 up
sudo ip netns exec loxilight bridge fdb add to 06:02:02:03:04:06 dst 3.3.3.2 dev hsvxlan51
sudo ip netns exec loxilight bridge fdb add to 06:02:02:03:04:06 dst 3.3.3.2 dev hsvxlan51 master

## Create two L3 hosts l3vxh1 and l3vxh2 which communicate over vxlan over loxilight namespace
## We call them l3 because communication between them happens over routing on top of vxlan.

## Setup l3vxh1
sudo ip -n loxilight link add hs7 type veth peer name eth0 netns l3vxh1
sudo ip -n loxilight link set hs7 up
sudo ip -n l3vxh1 link set eth0 up
sudo ip netns exec l3vxh1 ifconfig eth0 17.17.17.1/24 up
sudo ip netns exec l3vxh1 ip route add default via 17.17.17.254

## Setup l3vxh2
sudo ip netns exec l3vxh2 ifconfig eth0 8.8.8.1/24 up
sudo ip netns exec l3vxh2 ip link add vxlan78 type vxlan id 78 local 8.8.8.1 dev eth0 dstport 4789
sudo ip netns exec l3vxh2 ifconfig vxlan78 78.78.78.1/24 up
sudo ip netns exec l3vxh2 ip addr add 18.18.18.1/24 dev vxlan78
sudo ip netns exec l3vxh2  bridge fdb append 00:00:00:00:00:00 dst 8.8.8.254 dev vxlan78
sudo ip netns exec l3vxh2 ip route add default via 78.78.78.254
sudo ip netns exec loxilight ip route add 18.18.18.0/24 via 78.78.78.1

## Setup loxilight vxlan
sudo ip netns exec loxilight ifconfig hs7 17.17.17.254/24 up
sudo ip -n loxilight link add hs8 type veth peer name eth0 netns l3vxh2
sudo ip -n loxilight link set hs8 up
sudo ip -n l3vxh2 link set eth0 up
sudo ip netns exec loxilight brctl addbr hsvlan8
sudo ip netns exec loxilight brctl addif hsvlan8 hs8
sudo ip netns exec loxilight ip link set hsvlan8 up
sudo ip netns exec loxilight ip addr add 8.8.8.254/24 dev hsvlan8
sudo ip netns exec loxilight ip link add hsvxlan78 type vxlan id 78 local 8.8.8.254 dev hsvlan8 dstport 4789
sudo ip netns exec loxilight ip link set hsvxlan78 up
sudo ip netns exec loxilight ifconfig hsvxlan78 78.78.78.254/24 up
sudo ip netns exec loxilight bridge fdb append 00:00:00:00:00:00 dst 8.8.8.1 dev hsvxlan78
