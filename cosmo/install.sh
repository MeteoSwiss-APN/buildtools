#!/usr/bin/env bash
# Special options for Kesch
export LD_LIBRARY_PATH=${CRAY_LD_LIBRARY_PATH}:${LD_LIBRARY_PATH}
export TARGET_HOST=kesch

# COSMO Version
export COSMO_VERSION=5.0_2016.3
# COSMO Repository
export COSMO_REPOSITORY="git@github.com:MeteoSwiss-APN/cosmo-pompa.git"
# STELLA Repository
export STELLA_REPOSITORY="git@github.com:MeteoSwiss-APN/stella.git"
# Installation directory for COSMO/STELLA/Dycore (creates bin/lib/etc folders)
export INSTALLATION_DIR=$(pwd)/install
# COSMO Dependencies directory
export COSMO_DEPDENCIES_DIR=/project/c01/install/kesch/
# Code/build dir
export CODE_DIR=$(pwd)/code
# Installation path of boost (version 1.49+ supported)
export BOOST_ROOT=/apps/escha/UES/RH6.7/easybuild/software/Boost/1.49.0-gmvolf-15.11-Python-2.7.10/
# Single/Double precision (on: single precision, off: Double precision)
export ENABLE_SINGLE_PRECISION=OFF
# Enable the CPP dycore
export ENABLE_CPP_DYCORE=ON
# Enable cuda
export ENABLE_CUDA=ON
# Disable the serialization (used for debugging)
export ENABLE_COSMO_SERIALIZATION=OFF
# Nvidia CUDA architecture
export NVIDIA_CUDA_ARCH="sm_37"
# C Compiler
export CC=gcc
# C++ Compiler (gnu recommended)
export CXX=g++
# The number of build threads
export MAKE_BUILD_THREADS=6
# Build type: Release/Debug
export BUILD_TYPE=Release
# COSMO Compiler setup: cray/pgi/gnu
export COSMO_COMPILER=cray # The compiler used for the COSMO Fortran code

# The log file
build_logfile=$(pwd)/log

function run_command {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo "error with $1" >&2
        exit 1
    fi
    return $status
}

echo "Installing COSMO with the C++ Dycore into $INSTALLATION_DIR" > ${build_logfile}
mkdir -p $INSTALLATION_DIR
mkdir -p $CODE_DIR
pushd code > /dev/null
    echo "Downloading COSMO" 
    test -d COSMO || git clone $COSMO_REPOSITORY COSMO 2>&1 1>> ${build_logfile}
    pushd COSMO > /dev/null
        git fetch 2>&1 1>> ${build_logfile}
        git checkout $COSMO_VERSION 2>&1 1>> ${build_logfile}
        # STELLA Version requirement
        export STELLA_VERSION=$(cat STELLA_VERSION )
    popd > /dev/null
    
    echo "Downloading STELLA"
    test -d STELLA || git clone $STELLA_REPOSITORY STELLA 2>&1 1>> ${build_logfile}
    pushd STELLA > /dev/null
        echo "Configuring and compiling STELLA ${STELLA_VERSION}"
        git fetch
        run_command git checkout $STELLA_VERSION 2>&1 1>> ${build_logfile}
        mkdir -p build
        pushd build > /dev/null
            echo "Building STELLA"
            # Enable the x86_backend by default
            x86_backend=ON
            if [ "${ENABLE_CUDA}" == "ON" ] ; then
                cuda_backend=ON
            else
                cuda_backend=OFF
            fi
            # Recommended STELLA CONFIGURATION
            test -n "${ENABLE_GCL}" || ENABLE_GCL="ON"
            test -n "${ENABLE_PERFORMANCE_METERS}" || ENABLE_PERFORMANCE_METERS="OFF"
            test -n "${ENABLE_CACHING}" || ENABLE_CACHING="ON"
            test -n "${ENABLE_LOGGING}" || ENABLE_LOGGING="OFF"
            test -n "${ENABLE_STREAMS}" || ENABLE_STREAMS="ON"
            test -n "${ENABLE_BENCHMARK}" || ENABLE_BENCHMARK="ON"
            test -n "${ENABLE_COMMUNICATION}" || ENABLE_COMMUNICATION="ON"
            test -n "${ENABLE_SERIALIZATION}" || ENABLE_SERIALIZATION="ON"
            test -n "${ENABLE_TESTING}" || ENABLE_TESTING="ON"

            CMAKEARGS=(..
                "-DCMAKE_INSTALL_PREFIX=${INSTALLATION_DIR}"
                "-DCMAKE_BUILD_TYPE=${BUILD_TYPE}"
                "-DBoost_INCLUDE_DIR=${BOOST_ROOT}/include"
                "-DSINGLEPRECISION=${ENABLE_SINGLE_PRECISION}"
                "-DGCL=${ENABLE_GCL}"
                "-DENABLE_PERFORMANCE_METERS=${ENABLE_PERFORMANCE_METERS}"
                "-DENABLE_CACHING=${ENABLE_CACHING}"
                "-DLOGGING=${ENABLE_LOGGING}"
                "-DSTELLA_ENABLE_BENCHMARK=${ENABLE_BENCHMARK}"
                "-DSTELLA_ENABLE_COMMUNICATION=${ENABLE_COMMUNICATION}"
                "-DSTELLA_ENABLE_SERIALIZATION=${ENABLE_SERIALIZATION}"
                "-DSTELLA_ENABLE_TESTING=${ENABLE_TESTING}"
            )

            if [ "${x86_backend}" == "ON" ] ; then
                CMAKEARGS+=("-DX86_BACKEND=ON"
                            "-DENABLE_OPENMP=OFF"
                )
            else
                CMAKEARGS+=("-DX86_BACKEND=OFF")
            fi
            if [ "${cuda_backend}" == "ON" ] ; then
                CMAKEARGS+=("-DCUDA_BACKEND=ON"
                            "-DENABLE_CUDA_STREAMS=${ENABLE_STREAMS}"
                            "-DCUDA_COMPUTE_CAPABILITY=${NVIDIA_CUDA_ARCH}"
                )
            else
                CMAKEARGS+=("-DCUDA_BACKEND=OFF")
            fi

            #rm -rf *
            run_command cmake .. "${CMAKEARGS[@]}" 2>&1 1>> ${build_logfile}
            run_command make install -j $MAKE_BUILD_THREADS 2>&1 1>> ${build_logfile}
        popd > /dev/null
    popd > /dev/null
    pushd COSMO > /dev/null
        pushd dycore > /dev/null
            echo "Building the C++ Dycore"
            CMAKEARGS_BARE=(..
               "-DCMAKE_INSTALL_PREFIX=${INSTALLATION_DIR}"
               "-DSTELLA_DIR=${INSTALLATION_DIR}"
               "-DCMAKE_BUILD_TYPE=${BUILD_TYPE}"
               "-DBoost_INCLUDE_DIR=${BOOST_ROOT}/include"
               "-DSINGLEPRECISION=${ENABLE_SINGLE_PRECISION}"
               "-DLOGGING=${ENABLE_LOGGING}"
               "-DENABLE_PERFORMANCE_METERS=${ENABLE_PERFORMANCE_METERS}"
               "-DGCL=${ENABLE_GCL}"
               "-DENABLE_OPENMP=OFF"
            )
            
            # Compile and install the dycore for GPU
            if [ "${ENABLE_CUDA}" == "ON" ] ; then
                echo "    Building in GPU mode"
                mkdir -p build_cuda
                pushd build_cuda > /dev/null
                    CMAKEARGS=(..
                        "-DCUDA_BACKEND=ON"
                        "-DDYCORE_CUDA_COMPUTE_CAPABILITY=${NVIDIA_CUDA_ARCH}"
                    )
                    run_command cmake .. "${CMAKEARGS[@]}" "${CMAKEARGS_BARE[@]}" 2>&1 1>> ${build_logfile}
                    run_command make install -j $MAKE_BUILD_THREADS 2>&1 1>> ${build_logfile}
                popd > /dev/null
            fi

            # Compile and install the dycore for CPU 
            echo "    Building in CPU mode"
            mkdir -p build
            pushd build > /dev/null
                CMAKEARGS=(..
                    "-DCUDA_BACKEND=OFF"
                )
                run_command cmake .. "${CMAKEARGS[@]}" "${CMAKEARGS_BARE[@]}" 2>&1 1>> ${build_logfile}
                run_command make install -j $MAKE_BUILD_THREADS 2>&1 1>> ${build_logfile}

            popd > /dev/null
            echo "    Finished"
        popd > /dev/null
        pushd cosmo > /dev/null
            echo "Building COSMO"

            export STELLA_DIR=${INSTALLATION_DIR}
            export DYCORE_DIR=${INSTALLATION_DIR}

            nolib="OFF"
           
            architecture="cpu"
            [ "${ENABLE_CUDA}" == "ON" ] && architecture="gpu" 
            # set build target
            cppdycore_flag=""
            if [ $nolib == "ON" ] ; then
                if [ $debug == "ON" ] ; then
                    cosmo_build_target=nolibdebug;
                else
                    cosmo_build_target=nolibopt;
                fi
            else
                if [ $BUILD_TYPE == "Debug" ] ; then
                    cosmo_build_target=pardebug;
                else
                    cosmo_build_target=paropt;
                fi
                if [ $ENABLE_CPP_DYCORE == "ON" ] ; then
                    cppdycore_flag="CPP_DYCORE=1"
                fi
            fi

            # set up machine-specific Options file
            /bin/rm -f Options
            if [ $nolib == "ON" ] ; then
                optionsbase=Options.nolib
            else
                optionsbase=Options.${TARGET_HOST}.${COSMO_COMPILER}.${architecture}
            fi
            test -f ${optionsbase} || echo ${LINENO} "cannot locate options file ${optionsbase}" || exit 1

            if [ -f /bin/sed ] ; then
                SED=/bin/sed
            else
                SED=sed
            fi
            # make sure single precision choice is respected
            if [ "${ENABLE_SINGLE_PRECISION}" == "ON" ] ; then
                ${SED} s\|'^.*PFLAGS  *+= *-DSINGLEPRECISION'\|'PFLAGS  += -DSINGLEPRECISION'\|g < $optionsbase > Options
                ${SED} -i s\|'_double'\|'_float'\|g Options
            else
                ${SED} s\|'^.*PFLAGS  *+= *-DSINGLEPRECISION'\|'#PFLAGS  += -DSINGLEPRECISION'\|g < $optionsbase > Options
                ${SED} -i s\|'_float'\|'_double'\|g Options
            fi

            # get compiler
            fc=`grep '^F90  *=  *' Options | awk '{print $3}'`
            fc=`which ${fc}`

            # catch error and print some info
            if [ $? -ne 0 ]; then
                echo "Program F90 not found in Options file:"
                ls -l Options
                cat Options
            fi

            # set serialization
            if [ "${serialize}" == "ON" ]; then
                serialize_option="SERIALIZE=1"
            else
                serialize_option=""
            fi
            
            library=cosmo
            # nice message to user
            echo "      --------------------------------------------"
            echo "      setup ${library}"
            echo "      --------------------------------------------"
            echo "      Fortran compiler  :  ${COSMO_COMPILER}"
            echo "      Compile command   :  ${fc}"
            echo "      Target            :  ${cosmo_build_target}"
            echo "      Options base file :  ${optionsbase}"
            echo "      --------------------------------------------"
    
            # start the build
            if [ ${ENABLE_COSMO_SERIALIZATION} == "ON" ] ; then
                cosmo_logfile=`pwd`/serialize.log
                exe=${library}_serialize
            else
                cosmo_logfile=`pwd`/build.log
                exe=${library}
            fi
            echo > $cosmo_logfile
            echo "    >>>>>>>>>>> building executable ${exe} (see ${cosmo_logfile})"
            /bin/rm -rf ${exe}
            
            export INSTALL_DIR=$COSMO_DEPDENCIES_DIR
            export COMPILER=$COSMO_COMPILER
            # COSMO Make Command
            cmd="make ${serialize_option} ${cppdycore_flag} ${cosmo_build_target} -j ${MAKE_BUILD_THREADS}"
            echo "    >>> CMD: ${cmd}"
            # Run the cosmo make command
            ${cmd} >> ${cosmo_logfile} 2>&1
            res=$?
            if [ ! -f ${exe} ] ; then
                echo "NOTE: Problem encountered while compiling..."
                exit 1
            fi
            echo "Checking file"
            # check build success
            pattern='[^_]error|fail|Accelerator region ignored|Unrecognized ACC directive'
            egrep -i "${pattern}" ${cosmo_logfile} | egrep -v ' 0 errors|strerror' &>/dev/null
            if [ $? -eq 0 ]; then
                echo "==== START LOG: ${cosmo_logfile} ===="
                cat ${cosmo_logfile}
                echo "==== END LOG: ${cosmo_logfile} ===="
                echo "ERROR: the error search pattern produced a match"
                echo "PATTERN: ${pattern}"
                echo "OFFENDING LINES IN ${cosmo_logfile}:"
                \egrep -i "${pattern}" ${cosmo_logfile} | egrep -v ' 0 errors|strerror'
                echo ${LINENO} "error detected in build log (see log above)" 
                exit 1
            fi
            if [ ${res} -ne 0 ]; then
                echo "==== START LOG: ${cosmo_logfile} ===="
                cat ${logfile}
                echo "==== END LOG: ${cosmo_logfile} ===="
                echo ${LINENO} "non-zero exit status from make command (see log above)"
                exit 1
            fi
            if [ ! -f ${exe} ]; then
                echo "==== START LOG: ${cosmo_logfile} ===="
                cat ${logfile}
                echo "==== END LOG: ${cosmo_logfile} ===="
                echo ${LINENO} "cannot locate executable ${exe} (see log above)"
                exit 1
            fi
            echo "    success"
            target_path=${INSTALLATION_DIR}/bin/${exe}_${architecture}_${BUILD_TYPE}
            cp ${exe} ${target_path}
            echo "Installed ${exe} to ${target_path}"
        popd > /dev/null
    popd > /dev/null
popd > /dev/null

