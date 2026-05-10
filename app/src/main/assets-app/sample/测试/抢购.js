/**
 * 抢购脚本 - 执行抢购操作
 * Session 内容保存在 filesDir/snipe/ 目录下
 */

let session1 = "", session2 = "";
try {
    let basePath = context.filesDir.path;
    session1 = files.read(basePath + "/snipe/session1.txt") || "";
    session2 = files.read(basePath + "/snipe/session2.txt") || "";
} catch (e) {
    console.error("读取配置失败: " + e);
}

console.log("========== 开始抢购 ==========");
console.log("Session1: " + session1);
console.log("Session2: " + session2);

// 模拟点击操作
console.log("点击抢购按钮...");

// 模拟使用输入内容
if (session1) {
    console.log("使用 Session1 内容...");
}
if (session2) {
    console.log("使用 Session2 内容...");
}

console.log("✅ 抢购已提交");