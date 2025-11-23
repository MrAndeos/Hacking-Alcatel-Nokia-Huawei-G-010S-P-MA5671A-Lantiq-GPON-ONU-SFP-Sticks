# Alcatel/Nokia G-010S-P/G-010S-A, Huawei MA5671A: getting the most feature-packed firmware to work with Huawei MA5800 OLT

So I stumbled across the Alcatel G-010S-P GPON ONU stick on AliExpress for very cheap, and though it might be a fun way to break the 1Gbps barrier on GPON, as the module supports a 2.5Gbps link on the MAC (Media Access Controller) side via HSGMII.

The module came with some version of [this](https://mega.nz/folder/AvdGQAbZ#pH_GKzPqI8DhofLBthxd2w) firmware on it. I'll call this the "Chinese" firmware.
Having tested a few others, I consider this Chinese firmware to be the most feature-packed.

After editing the GPON SN/Vendor ID to HWTC (Huawei), the module would briefly register on the Huawei OLT (registration status 5) and work just fine for a couple minutes, but then disconnect and not register again for the next couple minutes.

# Digging deeper

## The flash layout {#flash-layout}

For most sticks, the general layout looks like this:
- mtd0 -> 000000 - 03FFFF (U-Boot)
- mtd1 -> 040000 - 0BFFFF (U-Boot env, some user configuration)
- mtd2 -> 0C0000 - 7FFFFF (image0, "linux")
- mtd5 -> 800000 - FFFFFF (image1)

Inside mtd2 and mtd5, there are actually 3 distinct partitions:
- The Linux kernel      (LZMA compressed data)
- mtd3 -> "rootfs"      (SquashFS image, read-only)
- mtd4 -> "rootfs_data" (JFFS2 image, overlayfs, contains OpenWRT configuration and all user-modified files)

The byte offset/location of mtd3/mtd4 within the image varies.

When booted from mtd5, the names are different ([source](https://hack-gpon.org/ont-huawei-ma5671a/#when-booting-from-image1)):
- mtd3 becomes mtd4
- mtd4 becomes mtd5


## Serial console access {#serial-console}

By default, none of the models of this module expose a serial console.
To make them do so, you have to set the following U-Boot variables:
```
# fw_setenv bootdelay 5
# fw_setenv asc0 0
# fw_setenv preboot
```
Once that is done, you should see debug output on the 3.3V TTL Serial console exposed on the SFP connector.
On which pins the console is located can differ depending on the module. See [here](https://hack-gpon.org/ont-nokia-g-010s-p/#serial) and [here](https://hack-gpon.org/ont-nokia-g-010s-a/#serial).
Here is how my initial attempt at this looked like:
![Image](./img/IMG20251106040415.jpg?raw=true)
The output seen here is all you get when the serial console and preboot output are not enabled.
Later, I've made this adapter for accessing the console more easily:
![Image](./img/IMG20251123125204.jpg?raw=true)
The full boot log can be found [here](./G-010S-P%20bootlog%20normal.txt?raw=true).


## Flashing firmware {#flashing-firmware}

### Via mtd write {#flashing-firmware-mtd-write}

Seems like you can pretty safely flash a different firmware image with ``mtd write`` when the stick is booted, has a network link and you have root access.
Before attempting this, I recommend [unlocking the serial console](#serial-console) to enable future debugging/recovery.
The new firmware image can be downloaded onto the stick's tmpfs using netcat.
On the sender:
```
# nc -l -p 13337 < mtd2.bin
```
On the stick:
```
# nc 192.168.100.254 13337 > /tmp/mtd2.bin
```
Wait about 20 seconds for the transfer to complete. For some reason, disabling the stdin input for nc on the stick doesn't work (see [here](https://superuser.com/a/98323/1204945)), so netcat doesn't exit by itself.

Next, verify that the checksums are the same:
```
# md5sum mtd2.bin
0e4cfdc1b96be6581869b26b48789556  mtd2.bin
```

It might be wise to mount the overlay filesystem (JFFS2) as read-only before flashing the new firmware. This should prevent any new writes, though I have not verified it:
```
# sync
# mount -o remount,ro /overlay
# mount -o remount,ro /
```

Flashing the firmware:
```
# mtd write mtd2.bin linux
Unlocking linux ...

Writing from mtd2.bin to linux ...
# reboot
```


### Via XMODEM {#flashing-firmware-xmodem}

I never tried! Some information can be found [here](https://github.com/tonusoo/koduinternet-cpe?tab=readme-ov-file#-small_blue_diamond-rooting-the-sfp-ont).

### Via an external hardware programmer {#flashing-firmware-external-programmer}

This is the "I'm desperate, it must work" method that I used the most.
With a cheap CH341A programmer, it's possible to read and write to the SPI flash chip after desoldering it from the module.
![Image](./img/IMG20251106055226.jpg?raw=true)
I recommend using the NeoProgrammer software with the CH341A.


## Booting image1 (mtd5) {#booting-image1}

The [Hack GPON guide](https://hack-gpon.org/ont-huawei-ma5671a/#cloning-of-mtd1-image-0-into-mtd5-image-1) says that this is all you have to do:
```
# fw_setenv committed_image 1
# fw_setenv image1_is_valid 1
```
However with my module, I also had to modify the ``bootcmd`` variable like this:
```
# fw_setenv bootcmd run flash_flash
```
As before it was set to ``bootcmd=run boot_image0``.


## Modifying the contents of the SquashFS and JFFS2 images {#modifying-the-squashfs-and-jffs2}

Inside this repo, I'm including some scripts for unpacking and repacking the filesystems, which allow for offline modification of the firmware images.
I've tested the SquashFS part and it worked fine (the module booted with the repacked fs).
The JFFS2 part should work for the most part (I compared generated JFFS2 images to originals and the structure looks identical), but I don't think that the current method of unpacking with [jefferson](https://github.com/sviehb/jefferson) and repacking with ``mkfs.jffs2`` works, because the information about whiteout files (modifications overlayed on top of SquashFS) is not recreated correctly.
Also, as mentioned before, the exact offsets and sizes of filesystems can differ.


## "The Huawei fix" {#huawei-fix}

To make the stick work stably with the Huawei OLT in my setup, I had to apply some modifications to the latest Chinese firmware (``基于新版固件修改版_2023.05.18/alcatel-g010sp_new_busybox-squashfs.image``).
I pulled the Huawei OMCI deamon (``huawei_fix/omcid-huawei``) from the original-rooted Huawei MA5671A firmware found [here](https://hack-gpon.org/ont-huawei-ma5671a/#list-of-firmwares-and-files).
As well as the OMCI MIB file (more info [here](https://hack-gpon.org/mib/)) used in the Huawei firmware by default (``huawei_fix/Huawei MA5671A OMCI MIB data_1g_8q.ini``).
Through some testing, I determined that the critical OMCI MEs are:
```
#hw
350 0 0 0 0 0 0x0000 0x00000000 0 0x00000000 0x00000000 0x0000 0x0000 0 0x0000 0x01080108 \x00\x00\x00\x00\x00\x00
353 2
376 0
373 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3
65427 370 0x5800 \x00\x43\x00\x63\x61\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
65427 376 0x8000 \x71\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
65427 65437 0xf000 \x41\x43\x41\x41\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
65427 350 0x0186 \x00\x00\x00\x00\x00\x00\x00\x43\x43\x00\x00\x00\x00\x51\x53\x00
65456 0 0xffff
```
Only the Huawei OMCID understands those MEs.

### Here is the full modification procedure: {#huawei-fix-modification-procedure}
1. Use the web UI to change the OMCID log level to 4.
    This prevents a log spam in ``/tmp/log/debug``. Without it, the tmpfs gets filled quickly, and the web UI becomes inaccessible.
    The Huawei OMCID supports only 5 log levels ``0-4``.
    This setting can be found in the web UI: ``GPON -> 互操作兼容配置 -> 高级自定义设置 -> 设置OMCID日志级别``.
2. Modify the Chinese firmware's OMCI MIB.
    This can be done with vim on the stick:
    ```
    # vi /etc/mibs/nameless.ini
    ```
    - You need to remove the 9th parameter from ME ``#336`` and the 5th parameter from ME ``#131``. So edit this:
        ```
        # ONU dynamic power management control
        336 0 0x3 0x0 0 0 0 0 0 0x0000000000000000

        # OLT-G
        131 0 "    " "                    " "              " 0x0000000000000000000000000000
        ```
        to this:
        ```
        # ONU dynamic power management control
        336 0 0x3 0x0 0 0 0 0 0

        # OLT-G
        131 0 "    " "                    " "              "
        ```

    - Next, add the Huawei OMCI MEs from above to the end of the file.
    - You can also uncomment the ME ``#347`` (IPv6 host config data).
3. Install the Huawei OMCID.
    In this step, the Huawei OMCID gets copied to the omcid location on the stick, overwriting the default one located in SquashFS.
    - Use the netcat transfer method from [Flashing firmware -> Via mtd write](#flashing-firmware-mtd-write) to transfer the new omcid to /tmp.
    - Replace the default omcid:
        ```
        chmod +x /tmp/omcid-huawei
        cp /tmp/omcid-huawei /opt/lantiq/bin/omcid
        ```
4. (optional, recommended) Keep the MAC side link active when no fiber is connected.
    This is needed to keep the module accessible over the network.
    Enable the following two checkboxes in the web UI: ``GPON -> 互操作兼容配置 -> 高级自定义设置 -> 禁用光纤状态检测, 禁用RX_LOS报告``.


## 2.5Gbps/HSGMII operation {#hsgmii-operation}

As stated in the introduction, for 2.5Gbps operation, the MAC has to support HSGMII.
There are quite few devices that expose this interface on an SFP.
The two that I considered were:
- A Broadcom BCM57810 based dual SFP+ NIC
- A "2.5G High Speed Fiber Optic Converter" box from AliExpress

Having already purchased a newer dual SFP+ NIC (Intel X710-DA2), I chose the latter.
![Image](./img/IMG20251119164057.jpg?raw=true)

It's worth noting that this device has the TTL Serial pins of the SFP ONU exposed on a standard Molex KK 254 compatible header inside the case, making access to the console super convenient.
![Image](./img/IMG20251119130924.jpg?raw=true)

And it's based on the [Realtek RTL8221B](https://www.realtek.com/Product/Index?id=4072&cate_id=786) chip.
![Image](./img/IMG20251119153741.jpg?raw=true)


## Final words {#final-words}

Happy speedtesting! :)
![Image](https://www.speedtest.net/result/18504053993.png)
![Image](./img/IMG20251119165439.jpg?raw=true)

I've been told that the latest R23 firmware for the Huawei MA5800 series includes further vendor-lock mechanisms that probably break compatibility with this hack. Our OLT is running the R18 firmware, which works fine even for XGS-PON boards.


## More useful links {#useful-links}

- https://github.com/hwti/G-010S-A
- https://github.com/njd90/G-010S-P_Bouygues
- https://lafibre.info/remplacer-livebox/guide-de-connexion-fibre-directement-sur-un-routeur-voire-meme-en-2gbps/5148/