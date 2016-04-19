# Instructions

Sample usage for kesch:

```
ssh ela.cscs.ch
ssh kesch.cscs.ch
cd /scratch/$(whoami)/
wget https://raw.githubusercontent.com/MeteoSwiss-APN/buildtools/master/cosmo/install.sh
chmod +x install.sh
module purge
source /project/c01/install/kesch/cosmo5/modules_fortran_gpu_double_release.env
./install.sh
```
