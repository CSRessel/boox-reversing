
```
readelf -d ../init | grep NEEDED
 0x0000000000000001 (NEEDED)             Shared library: [libbacktrace.so]
 0x0000000000000001 (NEEDED)             Shared library: [libbase.so]
 0x0000000000000001 (NEEDED)             Shared library: [libbootloader_message.so]
 0x0000000000000001 (NEEDED)             Shared library: [libcutils.so]
 0x0000000000000001 (NEEDED)             Shared library: [libext4_utils.so]
 0x0000000000000001 (NEEDED)             Shared library: [libfs_mgr.so]
 0x0000000000000001 (NEEDED)             Shared library: [libgsi.so]
 0x0000000000000001 (NEEDED)             Shared library: [libhidl-gen-utils.so]
 0x0000000000000001 (NEEDED)             Shared library: [libkeyutils.so]
 0x0000000000000001 (NEEDED)             Shared library: [liblog.so]
 0x0000000000000001 (NEEDED)             Shared library: [liblogwrap.so]
 0x0000000000000001 (NEEDED)             Shared library: [liblp.so]
 0x0000000000000001 (NEEDED)             Shared library: [libprocessgroup.so]
 0x0000000000000001 (NEEDED)             Shared library: [libprocessgroup_setup.so]
 0x0000000000000001 (NEEDED)             Shared library: [libselinux.so]
 0x0000000000000001 (NEEDED)             Shared library: [libc++.so]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so]
 0x0000000000000001 (NEEDED)             Shared library: [libm.so]
 0x0000000000000001 (NEEDED)             Shared library: [libdl.so]

readelf -d ./* | grep NEEDED
 0x0000000000000001 (NEEDED)             Shared library: [libadbd_fs.so]
 0x0000000000000001 (NEEDED)             Shared library: [liblog.so]
 0x0000000000000001 (NEEDED)             Shared library: [libselinux.so]
 0x0000000000000001 (NEEDED)             Shared library: [libbase.so]
 0x0000000000000001 (NEEDED)             Shared library: [libadb_protos.so]
 0x0000000000000001 (NEEDED)             Shared library: [libadbd_auth.so]
 0x0000000000000001 (NEEDED)             Shared library: [libcrypto.so]
 0x0000000000000001 (NEEDED)             Shared library: [libc++.so]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so]
 0x0000000000000001 (NEEDED)             Shared library: [libm.so]
 0x0000000000000001 (NEEDED)             Shared library: [libdl.so]
 0x0000000000000001 (NEEDED)             Shared library: [android.hardware.health@2.0.so]
 0x0000000000000001 (NEEDED)             Shared library: [libext4_utils.so]
 0x0000000000000001 (NEEDED)             Shared library: [libfs_mgr.so]
 0x0000000000000001 (NEEDED)             Shared library: [libhidlbase.so]
 0x0000000000000001 (NEEDED)             Shared library: [libutils.so]
 0x0000000000000001 (NEEDED)             Shared library: [libadbd_auth.so]
 0x0000000000000001 (NEEDED)             Shared library: [libadbd_fs.so]
 0x0000000000000001 (NEEDED)             Shared library: [libcrypto_utils.so]
 0x0000000000000001 (NEEDED)             Shared library: [liblog.so]
 0x0000000000000001 (NEEDED)             Shared library: [libselinux.so]
 0x0000000000000001 (NEEDED)             Shared library: [libbase.so]
 0x0000000000000001 (NEEDED)             Shared library: [libcrypto.so]
 0x0000000000000001 (NEEDED)             Shared library: [libc++.so]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so]
 0x0000000000000001 (NEEDED)             Shared library: [libm.so]
 0x0000000000000001 (NEEDED)             Shared library: [libdl.so]
 0x0000000000000001 (NEEDED)             Shared library: [libcrypto.so]
 0x0000000000000001 (NEEDED)             Shared library: [libz.so]
 0x0000000000000001 (NEEDED)             Shared library: [liblog.so]
 0x0000000000000001 (NEEDED)             Shared library: [libprocessgroup.so]
 0x0000000000000001 (NEEDED)             Shared library: [libselinux.so]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so]
 0x0000000000000001 (NEEDED)             Shared library: [libm.so]
 0x0000000000000001 (NEEDED)             Shared library: [libdl.so]
 0x0000000000000001 (NEEDED)             Shared library: [libbacktrace.so]
 0x0000000000000001 (NEEDED)             Shared library: [libbase.so]
 0x0000000000000001 (NEEDED)             Shared library: [libbootloader_message.so]
 0x0000000000000001 (NEEDED)             Shared library: [libcutils.so]
 0x0000000000000001 (NEEDED)             Shared library: [libext4_utils.so]
 0x0000000000000001 (NEEDED)             Shared library: [libfs_mgr.so]
 0x0000000000000001 (NEEDED)             Shared library: [libgsi.so]
 0x0000000000000001 (NEEDED)             Shared library: [libhidl-gen-utils.so]
 0x0000000000000001 (NEEDED)             Shared library: [libkeyutils.so]
 0x0000000000000001 (NEEDED)             Shared library: [liblog.so]
 0x0000000000000001 (NEEDED)             Shared library: [liblogwrap.so]
 0x0000000000000001 (NEEDED)             Shared library: [liblp.so]
 0x0000000000000001 (NEEDED)             Shared library: [libprocessgroup.so]
 0x0000000000000001 (NEEDED)             Shared library: [libprocessgroup_setup.so]
 0x0000000000000001 (NEEDED)             Shared library: [libselinux.so]
 0x0000000000000001 (NEEDED)             Shared library: [libc++.so]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so]
 0x0000000000000001 (NEEDED)             Shared library: [libm.so]
 0x0000000000000001 (NEEDED)             Shared library: [libdl.so]
```


```
libbacktrace.so
libbase.so
libbootloader_message.so
libcutils.so
libext4_utils.so
libfs_mgr.so
libgsi.so
libhidl-gen-utils.so
libkeyutils.so
liblog.so
liblogwrap.so
liblp.so
libprocessgroup.so
libprocessgroup_setup.so
libselinux.so
libc++.so
libc.so
libm.so
libdl.so
libadbd_fs.so
liblog.so
libselinux.so
libbase.so
libadb_protos.so
libadbd_auth.so
libcrypto.so
libc++.so
libc.so
libm.so
libdl.so
android.hardware.health@2.0.so
libext4_utils.so
libfs_mgr.so
libhidlbase.so
libutils.so
libadbd_auth.so
libadbd_fs.so
libcrypto_utils.so
liblog.so
libselinux.so
libbase.so
libcrypto.so
libc++.so
libc.so
libm.so
libdl.so
libcrypto.so
libz.so
liblog.so
libprocessgroup.so
libselinux.so
libc.so
libm.so
libdl.so
libbacktrace.so
libbase.so
libbootloader_message.so
libcutils.so
libext4_utils.so
libfs_mgr.so
libgsi.so
libhidl-gen-utils.so
libkeyutils.so
liblog.so
liblogwrap.so
liblp.so
libprocessgroup.so
libprocessgroup_setup.so
libselinux.so
libc++.so
libc.so
libm.so
libdl.so
```
