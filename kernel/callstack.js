const callStack = [];

var lispFormatFunction = null;

export function setLispFormatFunction(f) {
    lispFormatFunction = f;
}

export function pushCallStack(frame) {
    if (callStack.length > 1000) {
        raise('stack over flow');
    }
    callStack.push(frame);
}

export function popCallStack() {
    callStack.pop();
}

export function getBacktrace() {
    let s = 'Backtrace:\n';
    for (let i = callStack.length - 1, n = 0; i >= 0; i--, n++) {
        const frame = callStack[i];
        s += `${n}: `;
        try {
            s += lispFormatFunction("~S", frame);
        } catch (e) {
            s += `#<error printing ${e}>`;
        }
        if (i > 0) {
            s += '\n';
        }
    }
    return s;
}

export function raise(...args) {
    if (lispFormatFunction === null) {
        console.log(args);
        throw new Error();
    }
    let s = lispFormatFunction.apply(null, args);
    s += '\n\n';
    s += getBacktrace();
    throw new Error(s);
}
