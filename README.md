#Tiny-linux#

这是高级操作系统课程最后的大作业，主要实现的功能和要求如下：
+ 完成对linux的裁剪，形成一个满足要求的最小的Linux系统。
+ 要求用linux-4.0.4和 BusyBox 1.23.2 （用作shell+网络命令行工具），libc可以选择musl libc, uclibc等
+ 最终的系统可以用ifconfig等网络命令, 和简单的网络程序(完成100MB的tcp/ip传输)，可以在qemu 模拟的x86-64 或 x86-32中跑起来

附加功能：
+ 将应用程序busybox运行在内核态

从开始完全不懂linux内核裁剪，到最后的结果可以满足实验要求，整个课程中非常感谢[**杨海宇同学**](https://github.com/ir193/)以及[**杨松霖同学**](https://github.com/SunliyMonkey/)的帮助！！感谢他们能够抽出时间不厌其烦地回答我的问题，细心帮我解决实验中所遇到的问题！！
##项目构成与思路分析##
想要启动一个linux，需要两个必要的组成部分
>* linux内核镜像
>
>* 可挂载的文件系统镜像

这也是我们这个项目的两大组成部分。简单的来说，就是在一个文件系统镜像上启动linux内核，[linux内核的启动过程](http://blog.chinaunix.net/uid-27052262-id-3404074.html)按照如下步骤：
> 1.内核解压缩和重定位

> 2.Linux进入非压缩内核的入口，在非压缩的内核入口中，系统完成各种初始化任务

> 3.跳转到C语言的入口处startkernel（）运行

我们使用的内核是linux最终生成的bzImage，[具体生成过程](http://blog.chinaunix.net/uid-25909619-id-3380535.html)以及与vmlinux的区别有兴趣的同学可以详细阅读，这里不再赘述。

上面我们所提到的文件系统镜像，需要支持上述的两阶段引导过程，因此这里我们使用具有Linux初始RAM磁盘（initrd）。initrd是在系统引导过程中挂载的一个临时根文件系统，包含了各种可执行程序和驱动程序，它们可以用来挂载实际的根文件系统，然后再将这个 initrd RAM磁盘卸载，并释放内存。在本实验中，initrd就是最终的根文件系统。

接下来，我们对上述[两阶段引导过程](http://www.ruanyifeng.com/blog/2013/08/linux_boot_process.html)具体进一步详细分析：

> 1. 操作系统接管硬件以后，首先读入内核文件

>     这里的内核文件指的就是我们裁剪后生产的内核镜像bzImage

> 2. 启动初始化进程

>     内核文件加载以后，就开始运行第一个程序/sbin/init，它的作用是初始化系统环境。由于init是第一个运行的程序，它的进程编号（pid）就是1。其他所有进程都从它衍生，都是它的子进程。

> 3. 初始化进程启动daemon

>     许多程序需要开机启动，它们在Linux中被称为就叫做"守护进程"（daemon）。init进程的一大任务，就是去运行这些开机启动的程序。init进程首先读取文件 /etc/inittab，文件中指定了需要启动的daemon

>     接下来需要按照inittab中的内容加载开机启动程序，启动脚本通常统一放在/etc/init.d目录中。/etc/init.d 这个目录名最后一个字母d，是directory的意思，表示这是一个目录，用来与程序 /etc/init 区分。执行系统初始化命令行，缺省情况下会使用/etc/init.d/rcS

> 4. 用户登录

> 开机启动程序加载完毕以后，就要让用户登录了,打开login shell，整个linux启动的流程就结束了，自此用户直接与操作系统通过命令行或图形界面等方式进行交互。 

通过上述的分析，我们基本上清楚了linux内核的作用以及根文件系统initrd应该如何构建。因此我们的实验思路如下：
+ 编译生成linux内核bzImahe
+ 构建生成initrd根文件系统
+ 实现实验要求功能的设置
+ 对linux内核进行裁剪
+ 将应用程序busybox运行在内核态

接下来我们将给出详细的实验过程和步骤。

##编译 linux-4.0.4##
首先我们建立一个新的工程文件

        mkdir my-linux
        cd my-linux
        
下载所需要的linux内核，我们使用的是[linx-4.0.4](https://www.kernel.org/)版本的内核，现在最新版本的是4.0.5。可以选择手动下载，解压后放置在`my-linux/`目录下，也可以选择使用命令行的方式

        sudo apt-get install curl
        curl https://www.kernel.org/pub/linux/kernel/v4.x/linux-4.0.4.tar.xz | tar xjf -

现在你的`my-linux/`目录下包含了一个`linux-4.0.4/`的文件夹，其中是可以编译生成bzImage的源文件。为了后面对linux内核进行裁剪时的版本控制和调试，我们选择将make生成的文件和源文件分开存放。因此，可以使用如下命令对linux内核进行编译：

        mkdir obj
        mkdir obj/linux-defconfig
        cd linux-4.0.4
        make O=../obj/linux-defconfig defconfig

我们在`my-linux/obj/linux-defconig/`文件夹中存储了linux内核编译生成的Makefile等相应配置文件，采用的是默认的配置，其中`defconfige`默认为`x86_defconfig`，即生成的是64位内核文件，如需要生成32位内核文件，可以使用如下命令：

        make O=../obj/linux-defconfig i386_defconfig

这时我们对配置文件进行`make`就可以生成内核镜像，通过`-j`的参数指定编译时的线程数目

        cd ../obj/linux-defconfig
        make -j8

编译成功后，会看到如下信息：

> Kernel: arch/x86/boot/bzImage is ready  (#1)

由此也可以看出，生成的bzImage的位置，为了便于操作，我们将其移动到`obj/`的目录下

        cp arch/x86/boot/bzImage ../bzImage

至此，我们已经成功编译生成了一个内核镜像文件[bzImage](https://github.com/ChildIsTalent/tiny-linux/blob/master/original/bzImage),采用默认设置时其大小约为6M。

####Q & A####
* 在linux中执行`make defconfig`时提示`keep source code clean`

> 这种情况通常出现在多次编译linux内核时，因为上次编译只有有残留的配置文件，会影响到本次的编译。我们只需按照错误提示进入到源代码文件夹下进行清理就可以了

>       cd my-linux/linux-4.0.4
>       make mrproper

##编译 RAM Disk##

###使用BusyBox###

[BusyBox](http://baike.baidu.com/view/1429588.htm)是一种很常用的linux内核编译所需的工具，集成了一百多个最常用linux命令和工具。BusyBox包含了一些简单的工具，例如ls、cat和echo等等，还包含了一些更大、更复杂的工具，例grep、find、mount以及telnet。有些人将 BusyBox 称为 Linux 工具里的瑞士军刀。简单的说BusyBox就好像是个大工具箱，它集成压缩了 Linux 的许多工具和命令，也包含了 Android 系统的自带的shell。

下载[busybox](http://busybox.net)到`my-linux/`目录下

        cd my-linux
        curl http://busybox.net/downloads/busybox-1.23.2.tar.bz2 | tar xjf -

现在你的`my-linux/`目录下包含了一个`busybox-1.23.2/`的文件夹，同样地，为了后续的调试，我们选择将make生成的文件和源文件分开存放

        mkdir obj/busybox
        cd busybox-1.23.2
        make O=../obj/busybox defconfig
        
修改配置，使用静态编译busybox，否则在程序运行期间需要对相应的库进行动态加载，那么在根文件系统中则需要提供其所需的共享库。

        make O=../obj/busybox/ menuconfig

进入图形界面，选择

        -> Busybox Settings                                        
                -> Build Options     
                 [*] Build BusyBox as a static binary (no shared libs)         
        
现在编译生成的Makefile等配置文件即可

        cd ../obj/busybox/
        make -j8
        make install
        
此时可以在`my-linux/obj/busybox/`中看到生成的`_install`目录。通过下面的命令可以验证busybox是否安装正确：

        ./busybox ls

若可以成功输出当前目录下的文件，这说明busybox已经成功安装。

####Q & A####
* 在busybox中执行`make menuconfig`时报错缺少库文件
  
> 需要安装依赖库

>        sudo aptitab instab libncurses5-dev                                        

* 在busybox中执行`make defconfig`或`make menuconfig`时提示`keep source code clean`

> 这种情况通常出现在多次编译busybox时，因为上次编译只有有残留的配置文件，会影响到本次的编译。我们只需按照错误提示进入到源代码文件夹下进行清理就可以了

>       cd my-linux/busybox-1.23.2
>       make mrproper

* 编译配置文件执行`make -j8`时报错inetd.c未定义

> 关闭相应配置

>       -> Networking Utilities 
>       [ ] inetd

###生成initrd###

到目前为止，我们已经安装配置了busybox，接下来我们将使用该工具生成启动linux内核所必须的RAM Disk，即initrd。通过之前的分析，我们需要对初始进程和daemon进行设置。同样地，为了后续的调试方便和版本控制，我们将busybox生成的`_install`目录复制到其他位置。

        cd my-linux
        mkdir ramdisk
        cp -r obj/busybox/_install/* ramdisk/

* 设置初始化进程init

init 是程序运行的第一个程序，这里我们运行的就是busybox程序，采用符号链接的形式

        cd ramdisk
        ln -s bin/busybox init
        
* 设置开机启动程序

首先，我们需要先设定一些程序运行所需要的文件夹

        mkdir -pv {bin,sbin,etc,proc,sys,usr/{bin,sbin},dev}
        
init程序首先会访问`etc/inittab`文件，因此，我们需要编写inittab，指定开机需要启动的所有程序

        cd etc
        vim inittab
        
[inittab](https://github.com/ChildIsTalent/tiny-linux/blob/master/ramdisk/etc/inittab)文件的内容如下所示：

        ::sysinit:/etc/init.d/rcS
        
        ::askfirst:-/bin/sh
        
        ::restart:/sbin/init
        
        ::ctrlaltdel:/sbin/reboot
        
        ::shutdown:/bin/umount -a -r
        
        ::shutdown:/sbin/swapoff -a

* 编写系统初始化命令

从inittab文件中可以看出，首先执行的是`/etc/init.d/rcS`脚本，因此，我们生成初始化脚本

        mkdir init.d
        cd init.d
        vim rcS

[rcS](https://github.com/ChildIsTalent/tiny-linux/blob/master/ramdisk/etc/init.d/rcS)文件的内容如下所示：

        #!/bin/sh
        
        mount proc
        mount -o remount,rw /
        mount -a
        
        clear                               
        echo "My Tiny Linux Start :D ......"

将脚本文件赋予可执行的权限

        chmod +x rcS
        
在rcS脚本中，`mount -a` 是自动挂载 `/etc/fstab` 里面的东西，可以理解为挂在文件系统，因此我们还需要编写 `fstab`文件来设置我们的文件系统。

        cd ramdisk/etc/
        vim fstab
        
[fstab](https://github.com/ChildIsTalent/tiny-linux/blob/master/ramdisk/etc/fstab)文件内容如下：

        # /etc/fstab
        proc            /proc        proc    defaults          0       0
        sysfs           /sys         sysfs   defaults          0       0
        devtmpfs        /dev         devtmpfs  defaults          0       0

至此，我们已经完成了RAM Disk中相关文件的配置，可以压缩生成文件镜像了

        cd my-linux/ramdisk
        find . -print0 | cpio --null -ov --format=newc | gzip -9 > my-linux/obj/initramfs.cpio.gz   

`initramfs.cpio.gz`就是我们的根文件系统，位于`my-linux/obj/`中。拥有了linux内核镜像和文件系统，我们可以使用qemu来运行linux了,**注意bzImage和initramfs.cpio.gz均位于当前运行目录之下**。

        cd my-linux/obj
        qemu-system-x86_64 -kernel bzImage -initrd initramfs.cpio.gz
        
这时qemu上会显示出内核打印的各种信息，最终显示：

        My Tiny Linux Start :D ......
        Please press Enter to activate this console.
        
按`Enter`键后，就可以进入到文件系统中，运行命令

        ls /dev
        ls /proc
        ls /sys

可以看到各个文件夹下面都不为空，也就意味着`rcS`文件成功的访问了`fstab`文件，挂载了我们设置的文件系统。为了实现网络连接，我们首先要验证网卡是否正常工作

        ifconfig -a
        
在输出的信息中可以看到`eth0`，则说明网卡可以正常工作。

####Qemu使用小贴士####
linux系统启动后，可以使用`ctrl + a`的方式进入qemu monitor,qemu软件提供了很强大的[调试功能和命令](http://www.ibm.com/developerworks/cn/linux/l-cn-qemu-monitor/),有助于大家在发生异常时进行内核的单步调试。

实际上，qemu也提供无图形界面的启动方式，通过TTY将输出重定义到当前终端，命令如下：

        qemu-system-x86_64 -kernel bzImage -initrd initramfs.cpio.gz -append "console=ttyS0" -nographic

####Q & A####
* 启动linux内核时报错`Kernel panic at boot: not syncing. No init found.`

> 可能有如下原因：
> + busybox需要静态编译，注意在menuconfig中设置
> + init文件是通过符号连接到busybox，不能通过复制的方式产生。

* 没有`/proc /sys /dev`文件夹

> 这些文件夹不是busybox自动生成的，需要自己在`my-linux/ramdisk/`目录下创建

* linux内核启动后，`/proc`等文件夹下为空

> 文件系统没有正确挂载，检查`etc/fstab`以及`etc/rcS`文件是否编写正确

* 运行`ifconfig -a`命令时报错`/proc/net/dev: No such file or directory`

> 文件系统没有正确挂载，检查`etc/fstab`以及`etc/rcS`文件是否编写正确

* 找不到`eth0`

> 可能有以下几个原因
> + busybox的配置中没有使能网卡

>     重新运行 `make O=../busybox defconfig`，采用busybox默认设置。如仍不能解决问题，查看busybox是否为最新版本。

> + linux中没有开启网卡的driver

>     在`my-linux/linux-4.0.4`下运行如下命令
                
>               make O=../obj/linux-defconfig menuconfig

>  查找如下配置并将其开启

>               Device Drivers --> 
>                       Network device --> 
>                               Ethernet driver support --> Intel(R) PRO/1000 PCI Gigabit Ethernet support

> + qemu配置不当

>       可以尝试更新一下版本


####补充说明####
> 上述配置采用了busybox的默认配置，生成的文件系统比较大，但是拥有较多的功能。[这里](http://blog.csdn.net/ancjf/article/details/42172847)可以提供一个最简的busybox配置生成initrd文件系统的方法，削减了很多功能，但是按照这种配置方法可能会出现无法找到eth0的问题，因为配置中没有使能网卡。有兴趣的同学可以再继续深入研究busybox的配置问题。

> 在我们启动的linux系统当中，因为busybox的支持，可以执行大部分常见的命令，如ls,top，grep等等。但是当退出qemu后，这些改变并不会写回到根文件系统镜像当中。这是因为在运行时，是将相应的文件系统加载到内存当中，所有的操作都是在内存中进行的操作，在退出后并不会将改变写回文件镜像。

##网络连接##
实现网络连接的设置，我们需要在系统初始化命令中进行相应的设置，因此需要再次编写`etc/rcS`，增加如下内容：

        /sbin/ifconfig lo 127.0.0.1 up
        /sbin/route add 127.0.0.1 lo &
        
        ifconfig eth0 up
        ip addr add 10.0.2.15/24 dev eth0
        ip route add default via 10.0.2.2

更改了`rcS`文件后，我们需要重新生成文件系统镜像，即重新运行如下命令

        find . -print0 | cpio --null -ov --format=newc | gzip -9 > my-linux/obj/initramfs.cpio.gz   

这样，我们就可以启动系统来验证是否可以实现网络连接。简单起见，我们采用与本地主机相连的方式来验证。在本地使用python搭建一个http服务器，默认端口为8000

        python -m SimpleHTTPServer

使用`ifconfig`获得本地主机的ip，以166.111.134.134为例，在启动的linux内核中执行命令

        wget http://166.111.134.134:8000/file_name

其中file_name为你开启http服务器时所在路径下存在的某一文件，若网络连接成功，则可以看到该文件上传到了我们启动的文件系统镜像中。

####Q & A####
* 找不到文件

> 必须要保证要传输的文件和你开启http服务器时所在路径完全一致。

* 网络连接失败

> 在保证可以看到`eth0`的前提下，检查`rcS`是否正确更改，并且启动时使用的是更新后新的文件镜像

##linux内核裁剪##
###配置选项裁剪###
执行`make menuconfig`命令时，可以在配置见面中看到很多的linux内核配置选项，因为我们要实现一个功能极简的linux内核，所以其中绝大部分的功能是可以裁剪的。从每个选项的名称可以看出代表着内核的哪一部分功能，并且通过`</>`可以看到详细的功能说明。因此，我采用删掉一些功能后，进行编译生成内核镜像，测试是否仍能保证网络连接的方法一步一步进行裁剪。当熟悉了基本的流程和linux的各个功能部件后，我们可以使用如下命令

        cd my-linux
        mkdir obj/linux-prun
        cd linux-4.0.4
        
        make =O../obj/linux-prun allnoconfig
        make =O../obj/linux-prun menuconfig

重新建一个文件夹`linux-prun`是方便于版本控制。使用`allnoconfig`之后你就会发现，配置菜单中所有的选项都被清空了，这时只需要选择必须的配置项即可。

经过多次试验和测试，我得出了如下的最小配置：

**[最小配置](https://github.com/ChildIsTalent/tiny-linux/blob/master/original/config_file/config_final)**

> [*] 64-bit kernel 

> General setup --->

> 这里我们必须的功能有:支持可以挂在initrd根文件系统；可以解压gzip格式的根文件系统；优化size（这个我们后续会再解释）；支持标准的kerne feature，该选项是因为后面使能PCI时，才会出现PCI支持的相应配置。

>       [*] Initial RAM filesystem and RAM disk (initramfs/initrd) support
>       [*]   Support initial ramdisks compressed using gzip
>       [*] Optimize for size 
>       [*] Configure standard kernel features (expert users)  --->
>               [*] Enable PCI quitk workarounds

> Bus options --->

>       [*] PCI support  

> Executable file formats / Emulations ---> 

> 对各种文件格式的支持

>       Kernel support for ELF binaries 
>       Kernel support for scripts starting with #!

> Networking support --->

> 我们选择TCP/IP的通信连接方式

>       Networking options --->
>               [*] TCP/IP networking    

> Device Drivers --->

> 这里是我们所需的各部件驱动的配置：网卡驱动；字符设备驱动；串口驱动。我们最终选择非图形界面的方式运行linux内核，因为使用TTY重定向的方式，只需要串口驱动和字符设备驱动即可，可以最小化生成的内核。

>       [*] Network device support  --->  
>               [*] Ethernet driver support  --->   
>                       [*] Intel devices
>                         [*] Intel(R) PRO/1000 Gigabit Ethernet support

>      Character devices  ---> 
>                   [*] Enable TTY 
>                   Serial drivers  ---> 
>                       [*] 8250/16550 and compatible serial support
>                       [*]   Support 8250_core.* kernel options (DEPRECATED)
>                       [*]   Console on 8250/16550 and compatible serial port
>                       [*]   8250/16550 PCI device support
>                       (4)   Maximum number of 8250/16550 serial ports       
>                       (4)   Number of 8250/16550 serial ports to register at runtime 

32位系统的最小配置可以参考[杨海宇同学](https://github.com/ir193/tiny_linux)的配置。32位的最小配置对应用到64位上是不能直接运行的，缺少一些必要的配置信息。

###系统自带优化###

**1. 编译优化**

在上面的最小配置中，我们已经看到了如下选项

        General setup
               [*] Optimize for size
               
这是linux内核中自带的编译优化选项，可以对生成的bzImage的大小进行一定程度的优化。

**2. 压缩优化**

linux中提供了多种的bzImage压缩类型,如Gzip，Bzip2，LZMA，XZ，LZO，LZ4. 系统默认的压缩方式是Gzip，但实际上我们从[Work_on_Tiny_Linux_Kernel](http://elinux.org/Work_on_Tiny_Linux_Kernel)上可以看到如下说明：

> To get smallest size, lzma or XZ embedded may be the best choice, but to consider decompression speed, lzo may be the choice, the other two are more or less in-between.

因此，我们选择XZ的压缩方法，即设置如下

        General setup  
             Kernel compression mode (XZ)  --->

得到的结果是将之前的887K的内核直接缩减为729K

**3. 嵌入式模式**

linux内核通常用于嵌入式系统的开发，因此配置文件中提供了相应的选项

        General setup  
             [*] Embedded system
             
选择该选项之后，linux将按照嵌入式系统的方式进行编译，显然地，bzImage的内核会变小。

除了上述与嵌入式模式有关的选项外，[内存分配器](http://blog.csdn.net/adaptiver/article/details/7042469)也有相应的嵌入式模式

        General setup
                Choose SLAB allocator (SLOB (Simple Allocator))  --->
                
系统默认采用SLUB的模式，实际上，SLOB多用于嵌入式，所以我们选择SLOB，最终将bzImage的大小由729K降至726.5K.

经过上述所有优化，最终的[bzImage](https://github.com/ChildIsTalent/tiny-linux/blob/master/original/finalImage)大小为726.5K，运行所需内存为21.6M。运行所需内存可以使用qemu的`-m`参数来指定。可以通过如下命令进行验证：

        qemu-system-x86_64 -m 21.6 -kernel bzImage -initrd initramfs.cpio.gz -append "console=ttyS0" -nographic

####补充说明####

根据不同的需要，这里给出几种可选择的配置选项。

> **File systems 配置**

之前我们提到过，在启动linux内核后，检测 `/proc, /sys, /dev `不为空，即认为我们挂载上了文件系统。实际上，这是伪文件系统，即在内存中的文件系统。我们所使用的proc文件系统就是十分典型的一种伪文件系统。

> /proc file system support ───────────────────────┐

>  │ (there is a small number of Interrupt ReQuest lines in your computer    │  
>  │ that are used by the attached devices to gain the CPU's attention --    │  
>  │ often a source of trouble if two devices are mistakenly configured      │  
>  │ to use the same IRQ). The program procinfo to display some              │  
>  │ information about your system gathered from the /proc file system.      |

在之前的最小配置中，我们没有使能伪文件系统，因此在生成的内核启动后，无法使用top，ps等相关命令获取进程的信息。因此，这里我们提供一种可选配置

        File systems  --->   
                Pseudo filesystems  --->   
                        [*] /proc file system support   

开启该选项后，[bzImage](https://github.com/ChildIsTalent/tiny-linux/blob/master/original/finalImage_fs)大小将由之前最小的726.5K变为759.8K

> **printk 与 DNS解析配置**

同样地，为了最小化内核，我们关闭了很多不必要的功能。其中printk是输出内核启动信息的，即采用默认配置时，qemu启动过程中我们看到的以时间开通的内核信息

        General setup
               [*] Configure standard kernel features (expert users)  --->
                       [ ] Enable supprot for printk
        
在之前的配置中我们关闭了该选项。如果需要得到内核启动时打印的信息，则使能该选项。

网络连接中，我们同样关掉了DNS地址解析选项，即只能使用IP地址的方式访问网络。如果想要开启该选项,首先使能一个依赖库

        Network support --->
                [*]Ceph core library

这时才能在相应的位置找到DNS的配置选项。

        Network support --->    
                Network options --->
                        [*]DNS Resolver support
        
####Q & A####

在这个过程中遇到的问题很多，但大多数都是由于配置的依赖关系和裁剪不当导致的，期间反复尝试了很多次才达到了现在的这个最小配置，这里主要谈几点感想吧。

* 配置之间的依赖关系

按照实验的要求，配置的过程中主要围绕着网络驱动，TCP/IP通信支持来进行。实际上，因为配置之间的依赖关系，有些选项只有在其他前置选项打开后，才会出现；而开启某一选项的过程中，会出现一些自动打开的选项，对于这些选项，经过尝试后发现部分也可以选择性进行关闭。除此之外，使用allnoconfig也会默认开启一些配置选项，其中部分选项也可以进行关闭。

* driver模块化加载

课上[彭小祥同学](https://github.com/pxx199181/tiny_linux)提到了可以通过将driver模块化，提到bzImage外面，启动时动态加载，从而通过这种方式减小内核镜像的大小。我在最终的最小配置下进行了尝试，实际结果为730.9K，是比提取之前的镜像要更大。原因主要是将driver模块化时，内核配置中需要使能动态加载模块的相应配置，从而导致了最后内核反而变大。

同学们在尝试过程中可能还会发现，当吧driver移出后，系统没有办法通过命令行启动，这是因为对串口进行模块化后，就没有办法使能兼容串口控制台。之前的配置选项为：

        Device Drivers --->
                Character devices  ---> 
                   [*] Enable TTY 
                   Serial drivers  ---> 
                       [*] 8250/16550 and compatible serial support
                       [*]   Support 8250_core.* kernel options (DEPRECATED)
                       [*]   Console on 8250/16550 and compatible serial port
                       [*]   8250/16550 PCI device support
                       (4)   Maximum number of 8250/16550 serial ports       
                       (4)   Number of 8250/16550 serial ports to register at runtime 

模块化后，系统不再支持兼容串口控制台：

        Device Drivers --->
                Character devices  ---> 
                   [*] Enable TTY 
                   Serial drivers  ---> 
                       <M> 8250/16550 and compatible serial support
                       [*]   Support 8250_core.* kernel options (DEPRECATED)
                       <M>   8250/16550 PCI device support
                       (4)   Maximum number of 8250/16550 serial ports       
                       (4)   Number of 8250/16550 serial ports to register at runtime 

因此导致我们无法再通过TTY重定向到当前终端的非图形界面方式启动linux，这时只能采取增加相应driver后，用qemu图形界面来启动系统。

* 无图形内核启动方式
在之前最小配置中我们已经提到，选择非图形界面的方式运行linux内核，因为使用TTY重定向的方式，只需要串口驱动和字符设备驱动即可，可以最小化生成的内核。

因此在执行过程中一定要使用`-append "console=ttyS0" -nographic` 的选项，否则会发现qemu卡在Booting from ROM的地方。

##将应用程序运行在内核态##

###使用KML打补丁###

首先，我们需要明白什么是内核态和用户态。这里我给出一个比较简明的[博客](http://www.cnblogs.com/zemliu/p/3695503.html),在这里就不做详细的赘述。

将应用程序运行在内核态，用户程序可以直接访问内核地址空间，减少一些不必要的开销，如系统调用等，从而提升程序运行时间。与普通内核模块相比，运行在内核态的用户程序和其他进程一样，正常的执行调度和页面管理等。用户程序拥有特权级0，看似会给系统带来漏洞，但实际上有很多种方法可以保证内核的安全性，如静态类型检查、软件故障隔离等方法。

[Kernel Mode Linux](http://web.yl.is.s.u-tokyo.ac.jp/~tosh/kml/)就是实现了这种功能，提供了对应于不同版本的linux内核的补丁。这里我们就利用KML技术来实现将应用程序运行在内核态。

下载[补丁](http://web.yl.is.s.u-tokyo.ac.jp/~tosh/kml/kml/for4.x/)并解压

        cd my-linux
        curl http://web.yl.is.s.u-tokyo.ac.jp/~tosh/kml/kml/for4.x/kml_4.0_001.diff.gz | gunzip 

如果提示错误，找不到gunzip，则使用命令安装该解压软件

        sudo apt-get install gunzip
        
我们使用KML的补丁对linux-4.0.4进行修改

        cp -r linux-4.0.4/ patched-linux/
        cp kml_4.0_001.diff patched-linux/
        
        patch -p1 < ../kml_4.0_001.diff

这时会报错

        Hunk #1 FAILED at 1.
        1 out of 1 hunk FAILED -- saving rejects to file Makefile.rej
        
这是因为内核版本不匹配，导致Makefile无法被打补丁。因此，我们选择手动修改Makefile. 出错信息存储在Makefile.rej文件中
```
--- Makefile
+++ Makefile
@@ -1,7 +1,7 @@
 VERSION = 4
 PATCHLEVEL = 0
 SUBLEVEL = 0
-EXTRAVERSION =
+EXTRAVERSION = -kml
 NAME = Hurr durr I'ma sheep
```
因此我们手动更改Makefile文件的第4行，将其修改为

        EXTRAVERSION = -kml

此时重新编译linux内核，执行`make menuconfig`，使能KML

        Kernel Mode Linux  --->
                [*] Kernel Mode Linux           
                [*]   Check for chroot (NEW)      
                *** Safety check have not been implemented *** 

重新编译内核，生成[bzImage](https://github.com/ChildIsTalent/tiny-linux/blob/master/patched/finalImage)文件即可。

在github代码中，我们给出了三个不同的bzImage，分别是：
* [bzImage](https://github.com/ChildIsTalent/tiny-linux/blob/master/patched/bzImage)使用linux默认配置`defconfig`生成的支持KML的内核镜像
* [finalImage](https://github.com/ChildIsTalent/tiny-linux/blob/master/patched/finalImage)使用最小配置生成的支持KML的内核镜像
* [finalImage_fs](https://github.com/ChildIsTalent/tiny-linux/blob/master/patched/finalImage_fs)使用最小配置+使能伪文件系统的配置生成的支持KML的内核镜像

各个镜像对应的config文件在`tiny-linux/patched/config_files`目录下

###应用程序运行起来###

根据KML官方的使用说明，只需将想要运行在内核态的应用程序放置在`/trusted`文件夹下即可。因此，我们需要对之前制作的ramdisk进行修改

        cd my-linux
        cp -r ramdisk/ patched-ramdisk/
        cd patched-ramdisk
        mkdir trusted
        mv bin/busybox /trusted
        ln -s /trusted/busybox /bin/busybox

因为在`/bin以及/sbin`等文件夹下有着大量指向`/bin/busybox`的符号链接，因此我们只需创建一个链接`/bin/busybox`，将其指向真正的`/trusted/busybox`即可。

这时修改完成，我们需要生成一个新的文件系统

        find . -print0 | cpio --null -ov --format=newc | gzip -9 > my-linux/obj/initramfs-kml.cpio.gz
        
####补充说明####

课上陈老师指出，可以不用生成新的文件系统，只需要在linux内核启动后，在运行在内存的伪文件系统中进行相同的操作即可

        mkdir trusted
        mv bin/busybox /trusted
        ln -s /trusted/busybox /bin/busybox

###结果检测####

助教给了一个可以检测运行级别的小程序，是通过获取当前cs寄存器的低两位，来取得当前特权级。
```C
#include <stdio.h>
#include <stdint.h>

int main() {
    uint32_t cs;
    asm volatile("mov %%cs, %0" : "=r" (cs));
    printf("Privilege level: %x\n", cs & 0x3);
    return 0;
}
```
因为我们生成的内核和文件系统中没有gcc，所以需要在本地主机先进行静态编译生成可执行文件，再使用`wget`的方式将可执行文件上传。

        gcc -static-libsrdc++ -static-libgcc -static o test test.c

在以及启动的系统中，在根目录下运行`test`，可以看到程序运行在用户态

        chmod +x test
        ./test
        Pricilege level : 3

将程序移动到`trusted/`目录下，则可以看到程序运行在内核态

        cp test /trusted
        cd trusted
        ./test
        Pricilege leve ：0

####补充和说明####

之前我采用的是在qemu monitor中使用`info registers`命令查看cs寄存器的值来判断运行级别。经同学和老师指点，发现这种方法时不准确的。因为当使用`ctrl a then c`进入qemu monitor时，系统其实是处于处理中断的过程中，因为中断一定会跳到内核态，所以没有办法得知之前运行的进行处在什么特权级。

#参考资料#

主要的参考资料我在整个报告的过程中都以链接的形式放在里面了，这里再给出几个比较重要的参考文章。

* [How to Build A Custom Linux Kernel For Qemu](http://mgalgs.github.io/2015/05/16/how-to-build-a-custom-linux-kernel-for-qemu-2015-edition.html)
* [Work_on_Tiny_Linux_Kernel](http://elinux.org/Work_on_Tiny_Linux_Kernel)
* [Tiny Core Linux](http://distro.ibiblio.org/tinycorelinux/)



