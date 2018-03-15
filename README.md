# bluetoothChatInterfaces

开发了一套用于ios移动设备之间的蓝牙通讯接口
具备实现双方或者多方通信的必须接口，接口描述较详细，直接调用就可以实现ios设备间蓝牙通信。

attention！！！其中若使用bluetooth类，则必须实现bluetoothDelegate协议，协议中主要是require方法，这是为保证安全的通信而设计的。

待完成：传输文件，图片等；应该参考UDP传输大文件的方式实现。
