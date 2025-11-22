p1 = new Promise(
    (resolve, reject) => {
        // setTimeout(console.log(Datenow()), 1000)
        /* default return resolved */
    }
)
console.log(p1);
p1.then(() => console.log(p1))

/*  */

function go() {
    return new Promise(
        (resolve, reject) => {
            // ()=>console.log(Date.now())
            console.log("before run the setTimeout...");
            console.log(Date())
            // 期约解决之后(或者状态敲定之后,后续的than所添加的执行逻辑(回调)方可进入异步消息队列)
            setTimeout(resolve, 2000)
            console.log("after the setTimeout task be send to the async task queue.");
            console.log(Date())
            console.log("\n");
            /* default return resolved */
            // resolve()
        }
    )
}

function test_go() {
    go()
        .then(go)
        .then(go)
}

// 后续的then()中添加的操作会等待前面的操作期约返回结果
/* 等价于 */
/*
go()
.then(()=>go())
.then(()=>go())
 */

/* implement of simple clock: */
function clockByPromise() {
    // return 

    p = new Promise(
        (resolve) => {
            // ()=>console.log(Date.now())
            console.log(Date())
            setTimeout(resolve,1000)
        }
    )
    p.then(clockByPromise)
    // return p

}

// test_go()
clockByPromise()
