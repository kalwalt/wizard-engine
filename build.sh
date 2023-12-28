#!/bin/bash

function exit_usage() {
    echo "Usage: build.sh <wizeng|objdump|spectest|unittest> <x86-linux|x86-64-darwin|x86-64-linux|jvm|wave>"
    exit 1
}

if [ "$#" -lt 2 ]; then
    exit_usage
fi

V3C=${V3C:=$(which v3c)}
if [ ! -x "$V3C" ]; then
    echo "Virgil compiler (v3c) not found in \$PATH, and \$V3C not set"
    exit 1
fi

if [ "$VIRGIL_LIB" = "" ]; then
    if [ "$VIRGIL_LOC" = "" ]; then
	V3C_LOC=$(dirname $(which v3c))
	VIRGIL_LOC=$(cd $V3C_LOC/../ && pwd)
    fi
    VIRGIL_LIB=${VIRGIL_LOC}/lib/
fi

if [ ! -e "$VIRGIL_LIB/util/Vector.v3" ]; then
    echo "Virgil library code not found (searched $VIRGIL_LIB)."
    echo "Please set either: "
    echo "  VIRGIL_LOC, to the root of your Virgil installation"
    echo "  VIRGIL_LIB, to point directly to root of the library"
    exit 1
fi
    
ENGINE="src/engine/*.v3 src/util/*.v3 $VIRGIL_LIB/util/*.v3"
MONITORS="src/monitors/*.v3"
TARGET_V3="src/engine/v3/*.v3"
TARGET_X86_64="src/engine/compiler/*.v3 src/engine/x86-64/*.v3 $VIRGIL_LIB/asm/x86-64/*.v3"
UNITTEST="test/unittest/*.v3 test/wasm-spec/*.v3 test/unittest.main.v3"
UNITTEST_X86_64_LINUX="test/unittest/x86-64-linux/*.v3"
SPECTEST="test/wasm-spec/*.v3 test/spectest.main.v3"
WIZENG="src/wizeng.main.v3 src/modules/*.v3 src/modules/wizeng/*.v3"
WAVE="src/modules/wave/*.v3"
WASI="src/modules/wasi/*.v3"
WASI_X86_64_LINUX="src/modules/wasi/x86-64-linux/*.v3"

PROGRAM=$1
TARGET=$2

function make_build_file() {
	local target=$TARGET

	local build_time=$(date "+%Y-%m-%d %H:%M:%S")
	build_file="bin/Build-${TARGET}.v3"
	if [ "$release" == "release" ]; then
		local build_data="$target $build_time Release"
	else
		local build_data="$target $build_time by ${USER}@${HOST}"
	fi

        # TODO: handle case where build is not in a git repo
        REVS="$(git rev-list --count HEAD)"
	echo "var unused__ = (Version.buildData = \"$build_data\", Version.minorVersion = $REVS);" > $build_file

	echo $build_file
}


# compute sources
if [ "$PROGRAM" = "wizeng" ]; then
    SOURCES="$ENGINE $WIZENG $WAVE $WASI $MONITORS"
    if [[ "$TARGET" = "x86-64-linux" || "$TARGET" = "x86_64_linux" ]]; then
        SOURCES="$SOURCES $WASI_X86_64_LINUX"
    fi
elif [ "$PROGRAM" = "spectest" ]; then
    SOURCES="$ENGINE $SPECTEST"
elif [ "$PROGRAM" = "unittest" ]; then
    SOURCES="$ENGINE $UNITTEST"
    if [[ "$TARGET" = "x86-64-linux" || "$TARGET" = "x86_64_linux" ]]; then
        SOURCES="$SOURCES $UNITTEST_X86_64_LINUX"
    fi
elif [ "$PROGRAM" = "objdump" ]; then
    SOURCES="$ENGINE src/objdump.main.v3"
else
    exit_usage
fi

# make build file with target
BUILD_FILE=$(make_build_file)

PREGEN=${PREGEN:=1}

# build
exe=${PROGRAM}.${TARGET}
if [[ "$TARGET" = "x86-linux" || "$TARGET" = "x86_linux" ]]; then
    v3c-x86-linux -symbols -heap-size=512m -stack-size=1m $V3C_OPTS -program-name=${PROGRAM}.x86-linux -output=bin/ $SOURCES $BUILD_FILE $TARGET_V3
elif [[ "$TARGET" = "x86-64-darwin" || "$TARGET" = "x86_64_darwin" ]]; then
    v3c-x86-64-darwin -symbols -heap-size=700m -stack-size=1m $V3C_OPTS -program-name=${PROGRAM}.x86-64-darwin -output=bin/ $SOURCES $BUILD_FILE $TARGET_V3
elif [[ "$TARGET" = "x86-64-linux" || "$TARGET" = "x86_64_linux" ]]; then
    v3c-x86-64-linux -symbols -heap-size=700m -stack-size=2m $V3C_OPTS -program-name=${exe} -output=bin/ $SOURCES $BUILD_FILE $TARGET_X86_64
    if [ $PROGRAM = "wizeng" ]; then
	E=bin/${exe}
	if [ "$PREGEN" != 0 ]; then
            cp $E $E.pregen
            $E.pregen -pregen=$E > /tmp/wizeng.pregen.out 2>&1
	    if [ $? != 0 ]; then
		echo "warning: could not pregen code into $E, may be slower (see $E.pregen)"
	    else
		rm $E.pregen
	    fi
	else
	    echo "warning: skipped pregen of stubs in $E, may be slower"
	fi
    fi
elif [ "$TARGET" = "jvm" ]; then
    v3c-jar $V3C_OPTS -program-name=${PROGRAM}.jvm -output=bin/ $SOURCES $BUILD_FILE $TARGET_V3
elif [ "$TARGET" = "wave" ]; then
    # TODO: v3c-wave is not stable yet; compute its path from v3c
    V3C_PATH=$(which v3c)
    V3C_WAVE=${V3C_PATH/bin\/v3c/bin\/dev\/v3c-wave}
    $V3C_WAVE -symbols -heap-size=128m $V3C_OPTS -program-name=${PROGRAM} -output=bin/ $SOURCES $BUILD_FILE $TARGET_V3
elif [ "$TARGET" = "wali" ]; then
    # TODO: v3c-wave is not stable yet; compute its path from v3c
    V3C_PATH=$(which v3c)
    V3C_WAVE=${V3C_PATH/bin\/v3c/bin\/dev\/v3c-wali}
    $V3C_WAVE -symbols -heap-size=512m $V3C_OPTS -program-name=${PROGRAM} -output=bin/ $SOURCES $BUILD_FILE $TARGET_V3
elif [ "$TARGET" = "v3i" ]; then
    # check that the sources typecheck
    $V3C $SOURCES $TARGET_V3
    RET=$?
    if [ $RET != 0 ]; then
	exit $RET
    fi
    DIR=$(pwd)
    LIST=""
    for f in $SOURCES $TARGET_V3; do
	if [[ "$f" != /* ]]; then
	    f="$DIR/$f"
	fi
	LIST="$LIST $(ls $f)"
    done
    echo '#!/bin/bash' > bin/$PROGRAM.v3i
    echo "v3i \$V3C_OPTS $LIST" '$@' >> bin/$PROGRAM.v3i
    chmod 755 bin/$PROGRAM.v3i
    # run v3c just to check for compile errors
    $V3C $LIST
else
    exit_usage
fi
