#!/bin/bash -eE
# loosely based on https://gist.github.com/vishvananda/7094676

trap 'echo "An error occurred, try with verbose output (-v)."' ERR

function usage()
{
	echo "usage: $0 [-noo | -both] [-a] [-256] [-id ID1 ID2] [-v] <local_ip> <local_ifname> <remote_ip> <remote_ifname> <remote_hostname_for_ssh> [local_net] [remote_net]"
	echo "    Creates an ipsec tunnel between two machines, with offload on local"
	echo "    By default uses HW offload on local. -noo does not configure offload. -both configures offload on both ends"
	echo "    By default replaces existing tunnels. -a adds a tunnel instead"
	echo "    By default uses 128-bit crypto. -256 uses 256-bit crypto"
	echo "    By default the script prints nothing. -v verbose output"
	exit 1
}

FLUSH=1
SIZE=128

#ICV length 128
GCMSIZE=128

OFFLOAD=1
VERBOSE=0
FULL=0

while true ; do
	case "$1" in
		-none)  OFFLOAD=0; shift;;
		-local) OFFLOAD=1; shift;;
		-both) OFFLOAD=2; shift;;
		-full) FULL=1; shift;;
		-a)    FLUSH=0;   shift;;
		-256)  SIZE=256;  shift;;
		-id)   shift
		       ID_IN=$1;  shift
		       ID_OUT=$1; shift;;
		-v)    VERBOSE=1; shift;;
		-*) usage;;
		*) break;;
	esac
done

if (( "$#" < 5 )); then
	usage;
fi

SRC="$1"; shift
IFNAME="$1"; shift
DST="$1"; shift
REMOTE_IFNAME="$1"; shift
REMOTE="$1"; shift
# Optional arguments
LOCALNET="${1-$SRC}"; shift || true
REMOTENET="${1-$DST}"; shift || true

if (( $OFFLOAD >= 1 )) && \
   ! ip xfrm st help 2>&1 | grep -q offload; then
	echo "iproute2 doesn't support offload. Please update."
	exit 1
fi

if [ $OFFLOAD == 2 ] && \
   ! ssh $REMOTE "sudo /bin/bash -c 'ip xfrm st help'" 2>&1 | grep -q offload; then
	echo "iproute2 installed on \"$REMOTE\" doesn't support offload. Please update."
	exit 1
fi

if [ "$ID_IN" == "" ]; then
	ID_IN=0x`dd if=/dev/urandom count=4 bs=1 2> /dev/null| /usr/bin/xxd -p -c 8`
	ID_OUT=0x`dd if=/dev/urandom count=4 bs=1 2> /dev/null| /usr/bin/xxd -p -c 8`
fi

if [ $SIZE == 128 ]; then
	#KEYMAT 20 octets = KEY 16ocets, SALT 4octets
	KEY_IN=0x`dd if=/dev/urandom count=20 bs=1 2> /dev/null| /usr/bin/xxd -p -c 40`
	KEY_OUT=0x`dd if=/dev/urandom count=20 bs=1 2> /dev/null| /usr/bin/xxd -p -c 40`
else
	#KEYMAT 36 octets = KEY 32ocets, SALT 4octets	
	KEY_IN=0x`dd if=/dev/urandom count=36 bs=1 2> /dev/null| /usr/bin/xxd -p -c 72`
	KEY_OUT=0x`dd if=/dev/urandom count=36 bs=1 2> /dev/null| /usr/bin/xxd -p -c 72`
fi

echo $FULL
echo $OFFLOAD

OFFLOAD_OUT=
OFFLOAD_IN=
OFFLOAD_OUT_REMOTE=
OFFLOAD_IN_REMOTE=
if [ $FULL == 0 ]; then
	if [ $OFFLOAD == 2 ]; then
		OFFLOAD_OUT="offload dev $IFNAME dir out"
		OFFLOAD_IN="offload dev $IFNAME dir in"
		OFFLOAD_OUT_REMOTE="offload dev $REMOTE_IFNAME dir out"
		OFFLOAD_IN_REMOTE="offload dev $REMOTE_IFNAME dir in"
	elif [ $OFFLOAD == 1 ]; then
		OFFLOAD_OUT="offload dev $IFNAME dir out"
		OFFLOAD_IN="offload dev $IFNAME dir in"
	fi
elif [ $FULL == 1 ]; then
	if [ $OFFLOAD == 2 ]; then
		OFFLOAD_OUT="full_offload dev $IFNAME dir out"
		OFFLOAD_IN="full_offload dev $IFNAME dir in"
		OFFLOAD_OUT_REMOTE="full_offload dev $REMOTE_IFNAME dir out"
		OFFLOAD_IN_REMOTE="full_offload dev $REMOTE_IFNAME dir in"
	elif [ $OFFLOAD == 1 ]; then
		OFFLOAD_OUT="full_offload dev $IFNAME dir out"
		OFFLOAD_IN="full_offload dev $IFNAME dir in"
	fi
fi

[ $VERBOSE == 1 ] && set -x
if [ $FLUSH == 1 ]; then
	sudo ip xfrm state flush
	sudo ip xfrm policy flush
fi
sudo ip xfrm state add src $SRC dst $DST proto esp spi $ID_IN reqid $ID_IN mode transport aead 'rfc4106(gcm(aes))' $KEY_IN $GCMSIZE $OFFLOAD_OUT sel src $LOCALNET dst $REMOTENET
sudo ip xfrm state add src $DST dst $SRC proto esp spi $ID_OUT reqid $ID_OUT mode transport aead 'rfc4106(gcm(aes))' $KEY_OUT $GCMSIZE $OFFLOAD_IN sel src $REMOTENET dst $LOCALNET
sudo ip xfrm policy add src $LOCALNET dst $REMOTENET dir out tmpl src $SRC dst $DST proto esp reqid $ID_IN mode transport
sudo ip xfrm policy add src $REMOTENET dst $LOCALNET dir in tmpl src $DST dst $SRC proto esp reqid $ID_OUT mode transport
sudo ip xfrm policy add src $REMOTENET dst $LOCALNET dir fwd tmpl src $DST dst $SRC proto esp reqid $ID_OUT mode transport

#ssh $REMOTE /bin/bash << EOF
ssh -A -t root@$REMOTE /bin/bash << EOF
	[ $VERBOSE == 1 ] && set -x
	set -e
	if [ $FLUSH == 1 ]; then
		sudo ip xfrm state flush
		sudo ip xfrm policy flush
	fi
	sudo ip xfrm state add src $SRC dst $DST proto esp spi $ID_IN reqid $ID_IN mode transport aead 'rfc4106(gcm(aes))' $KEY_IN $GCMSIZE $OFFLOAD_IN_REMOTE sel src $LOCALNET dst $REMOTENET
	sudo ip xfrm state add src $DST dst $SRC proto esp spi $ID_OUT reqid $ID_OUT mode transport aead 'rfc4106(gcm(aes))' $KEY_OUT $GCMSIZE $OFFLOAD_OUT_REMOTE sel src $REMOTENET dst $LOCALNET
	sudo ip xfrm policy add src $REMOTENET dst $LOCALNET dir out tmpl src $DST dst $SRC proto esp reqid $ID_OUT mode transport
	sudo ip xfrm policy add src $LOCALNET dst $REMOTENET dir in tmpl src $SRC dst $DST proto esp reqid $ID_IN mode transport
	sudo ip xfrm policy add src $LOCALNET dst $REMOTENET dir fwd tmpl src $SRC dst $DST proto esp reqid $ID_IN mode transport
EOF

echo "IPSec tunnel configured successfully"

