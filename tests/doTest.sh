#!/bin/bash

THISFILE=$(realpath "$0")
TESTPATH=$(realpath $(dirname $0))
WOOFPATH=$(realpath "$TESTPATH"/../woof)
cd $TESTPATH

WOOFPID=""

trap 'echo "";echo "TEST FAILED!";echo $WOOFPID; kill $WOOFPID' SIGINT SIGTERM EXIT

announce() {
	set +x
	rm -rf testfile-curl*
	echo -e "\n\n"
	echo "================================================================================"
	echo "   $@"
	echo "================================================================================"
	set -x
}

woof() {
	python3 "$WOOFPATH" "$@" &
	WOOFPID=$!
	sleep 1
}

doCurl() {
	curl -v "$@" >$TESTPATH/testfile-curlout 2>$TESTPATH/testfile-curlerr
}

checkWoofDone() {
	sleep 1
	if kill $WOOFPID 2>/dev/null >/dev/null; then
		echo "woof was still alive"
		exit 1
	else
		echo "Woof has ended"
	fi
}

checkWoofNotDone() {
	sleep 1
	if kill $WOOFPID 2>/dev/null >/dev/null; then
		echo "woof was still alive"
	else
		echo "Woof has ended"
		exit 1
	fi
}

rm -rf testfile* testdir*
echo "Make some testfiles"

for i in {0..20}; do
	{
		echo $i
		cat "$THISFILE"
		date --iso-8601=ns
		echo $RANDOM | md5sum
	} | base64 >testfile$i
done
mkdir -p testdir testdirout{zip,bz2,gz,tar}
mv testfile?? testdir

set -xeo pipefail

#=======================================================
announce "Simple share test"
woof -c1 testfile1
doCurl -L "http://127.0.0.1:8080"
diff --report-identical testfile1 testfile-curlout
checkWoofDone

#=======================================================
announce "Simple share with count"
woof -c2 testfile1
doCurl -L "http://127.0.0.1:8080"
diff --report-identical testfile1 testfile-curlout
checkWoofNotDone
woof -c2 testfile1
doCurl -L "http://127.0.0.1:8080"
doCurl -L "http://127.0.0.1:8080"
diff --report-identical testfile1 testfile-curlout
checkWoofDone

#=======================================================
announce "Share of folder tar.gz"
woof -c1 testdir
doCurl -L "http://127.0.0.1:8080"
(
	cd testdiroutgz
	tar xzf ../testfile-curlout
)
diff --report-identical testdir testdiroutgz/testdir

#=======================================================
announce "Share of folder bzip2"
woof -j -c1 testdir
doCurl -L "http://127.0.0.1:8080"
(
	cd testdiroutbz2
	bzip2 -d ../testfile-curlout
	tar -xf ../testfile-curlout.out
)
diff --report-identical testdir testdiroutbz2/testdir
checkWoofDone

#=======================================================
announce "Share of folder zip"
woof -Z -c1 testdir
doCurl -L "http://127.0.0.1:8080"
(
	cd testdiroutzip
	unzip ../testfile-curlout
)
diff --report-identical testdir testdiroutzip/testdir
checkWoofDone

#=======================================================
announce "Share of folder no compression"
woof -u -c1 testdir
doCurl -L "http://127.0.0.1:8080"
(
	cd testdirouttar
	tar -xf ../testfile-curlout
)
diff --report-identical testdir testdirouttar/testdir
checkWoofDone

#=======================================================
announce "Share of self"
woof -c1 -s
doCurl -L "http://127.0.0.1:8080"
diff --report-identical testfile-curlout ../woof
checkWoofDone

#=======================================================
announce "Upload function"
woof -c1 -U
doCurl -L "http://127.0.0.1:8080"

# is there a upload field
xmllint --xpath 'string(//input[@type="file"]/@name)' --html testfile-curlout >testfile-curlout.fileinputname
echo "upfile" >testfile-curlout.fileinputname-expected
diff --report-identical testfile-curlout.fileinputname{,-expected}

# is there a submit button
xmllint --xpath '//input[@type="submit"]' --html testfile-curlout

# single upload test
doCurl -k -X POST -F 'upfile=@testdir/testfile10' "http://127.0.0.1:8080"
diff --report-identical testfile10 testdir/testfile10
checkWoofDone

# multiple upload test
woof -c20 -U
for i in {1..5}; do
	doCurl -k -X POST -F 'upfile=@testdir/testfile10' "http://127.0.0.1:8080"
	diff --report-identical testfile10.$i testdir/testfile10
done
checkWoofNotDone

if [ "6" -eq "$(ls testfile10* | wc -l)" ]; then
	echo "6 files found okido"
else
	echo "Incorrect number of files:"
	ls testfile10* | nl
	exit 1
fi

# reset trap

trap 'echo "Ended sucessfully"' SIGINT SIGTERM EXIT
rm -rf testfile* testdir*
exit 0
