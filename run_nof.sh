N=${1:-1}
REMOTE_SERVER="'10.7.159.36 -p 2222'"
./transport_perf.sh $N $REMOTE_SERVER full none p0 p0
