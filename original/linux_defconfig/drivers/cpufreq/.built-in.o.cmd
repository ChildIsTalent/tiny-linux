cmd_drivers/cpufreq/built-in.o :=  ld -m elf_x86_64   -r -o drivers/cpufreq/built-in.o drivers/cpufreq/cpufreq.o drivers/cpufreq/freq_table.o drivers/cpufreq/cpufreq_performance.o drivers/cpufreq/cpufreq_userspace.o drivers/cpufreq/cpufreq_ondemand.o drivers/cpufreq/cpufreq_governor.o drivers/cpufreq/acpi-cpufreq.o 