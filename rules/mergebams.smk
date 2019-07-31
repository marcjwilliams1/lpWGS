_merge_files(wildcards):
    return glob(wildcards.prefix + "_S[0-9]+\_L[0-9]+\.bam")

rule picard_merge_bam:
    input: _merge_files(wildcards)
    output: merge = "tempbams/{sample}.bam"
    run:
        inputstr = " ".join(["INPUT={}".format(x) for x in input])
        shell("java -jar picard command here with options {inputstr} OUTPUT={output}".format(inputstr=inputstr, ))
