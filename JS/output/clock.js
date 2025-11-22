/* define(set) a d(debug)function to learn about the program running details more easily! */
d = console.log;
function empty(p1 = "", p2 = "", p3 = "") {
    // empty
}
// d = empty;
inf = console.log;
function showSecond() {
    const d = new Date()
    return d.getSeconds()
}

async function clock(No = 0) {
    // defind a count:
    // No=1
    // console.log("hello clock!");
    d("-------🌏-------")
    d(`\n✔️start clock${No} :`, showSecond())
    d(`entering await${No}:`, showSecond())
    await new Promise(
        (resolve) => {
            d(`\t\tawait${No}`)
            d("\t\tin await block1:first statment:🕐", showSecond())
            console.log("\t⏰", showSecond());
            setTimeout(resolve, 1000)
            d("\t\tin await block2:after setTimeOut🕐", showSecond())
        })
    // d=inf
    d(`left(out of) await${No} :`, showSecond())
    d("\t\t🕐", showSecond(), "left await block just now.")
    // clock() is a async function,that will be pushed to async task queue,and return as soon as possible.
    clock(No + 1);
    /*
    新的clock()的启动几乎时瞬间完成的(从运行结果可以看出).然后又回到当前主线程执行未完任务
    clock是异步代码,在主线程将该任务快速排入到异步消息队列后,立刻回到主线程中执行尚未完成的任务,
    (这里的await代码中存在一些打印语句,主线程会直接执行打印语句(这些不是耗时逻辑,将在执行await 块之时会执行掉),
    而setTimeout()这种被认为时耗时逻辑的代码会被排入异步队列,而不是立刻执行,其余的非耗时逻辑则可以被一并执行掉
    由于async/await语法糖的缘故,await 代码块之外的逻辑将需要等await块的逻辑结束后才能得到执行)
    在本代码中,就是将inf()内容打印出来,这样,主线程中的任务(栈)就算执行完毕,
    此时异步消息队列可以弹入新的任务到主线程中进行处理 */
    inf(`🔶ended clock${No}!👬`, showSecond())
}

/* 尝试用while改写 */
async function clockCalledByWhile(No = 0) {

    await new Promise(
        (resolve) => {

            console.log("\t⏰", Date());
            setTimeout(resolve, 1000)
        })

}
async function testWhile() {

    while (true) {
         await clockCalledByWhile()
    }
    
}
/* 统一控制执行所编写的函数 */
// 查看函数的类型信息
console.log(clock);
// clock()
testWhile()




// /* define(set) a d(debug)function to learn about the program running details more easily! */
// d = console.log;
// function empty(p1 = "", p2 = "", p3 = "") {
//     // empty
// }
// d = empty;
// inf = console.log;
// function showSecond() {
//     const d = new showSecond()
//     return d.getSeconds()
// }

// async function clock(No = 0) {
//     // defind a count:
//     // No=1
//     // console.log("hello clock!");
//     d(`\nstart clock${No} :`)
//     d(`entering await:`)
//     await new Promise(
//         (resolve) => {
//             d("\t\tin await block1:first statment:", showSecond())
//             console.log("\t⏰", showSecond());
//             setTimeout(resolve, 1000)
//             d("\t\tin await block2:after setTimeOut", showSecond())
//         })
//     // d=inf
//     d(`left await .`)
//     d("\t\t🕐",, "left await block just now:")
//     // clock() is a async function,that will be pushed to async task queue,and return as soon as possible.
//     No++
//     clock(No);
//     inf(`clock() inner ${No} ended!👬`)
// }


// console.log(clock);
// clock()