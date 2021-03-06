#!/bin/bash

# If you adapt this script for your own use, you will need to set these two variables based on your environment.
# SV_DIR is the installation directory for SVToolkit - it must be an exported environment variable.
# SV_TMPDIR is a directory for writing temp files, which may be large if you have a large data set.
export SV_DIR=`cd .. && pwd`
SV_TMPDIR=./tmpdir

runDir=test1
bam=data/installtest.bam
sites=test1.discovery.vcf
genotypes=test1.genotypes.vcf

# These executables must be on your path.
which java > /dev/null || exit 1
which Rscript > /dev/null || exit 1
which samtools > /dev/null || exit 1

# For SVAltAlign, you must use the version of bwa compatible with Genome STRiP.
export PATH=${SV_DIR}/bwa:${PATH}
export LD_LIBRARY_PATH=${SV_DIR}/bwa:${LD_LIBRARY_PATH}

mx="-Xmx4g"
classpath="${SV_DIR}/lib/SVToolkit.jar:${SV_DIR}/lib/gatk/GenomeAnalysisTK.jar:${SV_DIR}/lib/gatk/Queue.jar"

mkdir -p ${runDir}/logs || exit 1
mkdir -p ${runDir}/metadata || exit 1

# Unzip the reference sequence and masks if necessary
if [ ! -e data/human_b36_chr1.fasta -a -e data/human_b36_chr1.fasta.gz ]; then
    gunzip data/human_b36_chr1.fasta.gz
fi
if [ ! -e data/human_b36_chr1.mask.fasta -a -e data/human_b36_chr1.mask.fasta.gz ]; then
    gunzip data/human_b36_chr1.mask.fasta.gz
fi
if [ ! -e data/cn2_mask_g1k_b36_chr1.fasta -a -e data/cn2_mask_g1k_b36_chr1.fasta.gz ]; then
    gunzip data/cn2_mask_g1k_b36_chr1.fasta.gz
fi

# Display version information.
java -cp ${classpath} ${mx} -jar ${SV_DIR}/lib/SVToolkit.jar

# Run preprocessing.
# For large scale use, you should use -reduceInsertSizeDistributions, but this is too slow for the installation test.
# The method employed by -computeGCProfiles requires a CN2 copy number mask and is currently only supported for human genomes.
java -cp ${classpath} ${mx} \
    org.broadinstitute.sting.queue.QCommandLine \
    -S ${SV_DIR}/qscript/SVPreprocess.q \
    -S ${SV_DIR}/qscript/SVQScript.q \
    -gatk ${SV_DIR}/lib/gatk/GenomeAnalysisTK.jar \
    --disableJobReport \
    -cp ${classpath} \
    -configFile conf/genstrip_installtest_parameters.txt \
    -tempDir ${SV_TMPDIR} \
    -R data/human_b36_chr1.fasta \
    -genomeMaskFile data/human_b36_chr1.mask.fasta \
    -ploidyMapFile data/human_b36_chr1.ploidy.map \
    -copyNumberMaskFile data/cn2_mask_g1k_b36_chr1.fasta \
    -genderMapFile data/installtest_gender.map \
    -runDirectory ${runDir} \
    -md ${runDir}/metadata \
    -disableGATKTraversal \
    -useMultiStep \
    -computeSizesInterval 1:61700000-61900000 \
    -computeGCProfiles \
    -jobLogDir ${runDir}/logs \
    -I ${bam} \
    -run \
    || exit 1

# Run discovery.
java -cp ${classpath} ${mx} \
    org.broadinstitute.sting.queue.QCommandLine \
    -S ${SV_DIR}/qscript/SVDiscovery.q \
    -S ${SV_DIR}/qscript/SVQScript.q \
    -gatk ${SV_DIR}/lib/gatk/GenomeAnalysisTK.jar \
    --disableJobReport \
    -cp ${classpath} \
    -configFile conf/genstrip_installtest_parameters.txt \
    -tempDir ${SV_TMPDIR} \
    -R data/human_b36_chr1.fasta \
    -genomeMaskFile data/human_b36_chr1.mask.fasta \
    -genderMapFile data/installtest_gender.map \
    -runDirectory ${runDir} \
    -md ${runDir}/metadata \
    -disableGATKTraversal \
    -jobLogDir ${runDir}/logs \
    -L 1 \
    -minimumSize 100 \
    -maximumSize 1000000 \
    -suppressVCFCommandLines \
    -I ${bam} \
    -O ${sites} \
    -run \
    || exit 1

(grep -v ^##fileDate= ${sites} | grep -v ^##source= | grep -v ^##reference= | diff -q - benchmark/${sites}) \
    || { echo "Error: test results do not match benchmark data"; exit 1; }

# Run genotyping on the discovered sites.
java -cp ${classpath} ${mx} \
    org.broadinstitute.sting.queue.QCommandLine \
    -S ${SV_DIR}/qscript/SVGenotyper.q \
    -S ${SV_DIR}/qscript/SVQScript.q \
    -gatk ${SV_DIR}/lib/gatk/GenomeAnalysisTK.jar \
    --disableJobReport \
    -cp ${classpath} \
    -configFile conf/genstrip_installtest_parameters.txt \
    -tempDir ${SV_TMPDIR} \
    -R data/human_b36_chr1.fasta \
    -genomeMaskFile data/human_b36_chr1.mask.fasta \
    -genderMapFile data/installtest_gender.map \
    -runDirectory ${runDir} \
    -md ${runDir}/metadata \
    -disableGATKTraversal \
    -jobLogDir ${runDir}/logs \
    -I ${bam} \
    -vcf ${sites} \
    -O ${genotypes} \
    -run \
    || exit 1

(grep -v ^##fileDate= ${genotypes} | grep -v ^##source= | grep -v ^##contig= | grep -v ^##reference= | diff -q - benchmark/${genotypes}) \
    || { echo "Error: test results do not match benchmark data"; exit 1; }

