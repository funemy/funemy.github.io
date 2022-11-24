title: Data Races, what are they, and why are they evil?
tags:
  - concurrency
date: 2020-08-01 23:10:00
---

### Race Conditions and Data Races

It is commonly known that writing concurrent programs can introduce a kind of bug that normally does not exist in single-threaded programs. Many people refer to them as “Races”, or “Race Conditions”.

You may also hear about people talking about a kind of bug called “Data Races”. For example, the simulation program for the COVID-19 pandemic was [questioned][covid-issue] about their correctness because of suspected potential “data races”. The discussions have caused quite some drama online.

[covid-issue]: https://github.com/mrc-ide/covid-sim/issues/161

So are data races the same as race conditions, given that they both share “race” in their names and have similar code patterns? This confuses a lot of people, and even some experienced developers.

Simply put, race conditions and data races are different. One is not even a subset of the other, which is a common [misunderstanding][so-question].

[so-question]: https://stackoverflow.com/questions/11276259/are-data-races-and-race-condition-actually-the-same-thing-in-context-of-conc

Race condition, according to its [wiki page][race-condition]:

> … is the condition of an electronics, software, or other system where the system’s substantive behavior is dependent on the sequence or timing of other uncontrollable events. It becomes a bug when one or more of the possible behaviors is undesirable.

[race-condition]: https://en.wikipedia.org/wiki/Race_condition

This definition implies race condition is not inherently a bug. Race conditions are inevitable as long as concurrent events exist in the system. Consider the following example:

```
// x is a shared variable
// Thread 1
x = 1
print x

// Thread 2
x = 999
```

There is clearly a race condition going on, where the result of `print x` is dependent on the sequence of assignments to `x`. However, whether it is a bug really depends on what we expect to be printed out, i.e., if the behavior is “desired”.

On the other hand, data race is clearly defined as a **bug**. Data race occurs when two memory accesses:

- are accessing the same piece of memory;
- are performed concurrently;
- have at least one write;
- are not protected by synchronization or locks.


The definition of “concurrently” is language-dependent. For example, the C++ Standard defines two actions as potentially concurrent if:

- they are performed by different threads, or
- they are unsequenced, and at least one is performed by a signal handler.

The second rule is [idiosyncratic to C++][cpp-standard]. The Java Language Specification gives a different [definition][jls].

[cpp-standard]: http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2014/n4296.pdf
[jls]: https://docs.oracle.com/javase/specs/jls/se12/html/jls-17.html#jls-17.4.5

Now re-examining the example above, we find it is also a “data race”. The concurrent accesses of `x` are unprotected, so it is a **BUG**!

A valid fix for this bug is to simply protect each access with a lock:

```
// x is a shared variable
// l is a global lock

// Thread 1
lock(l)
x = 1
unlock(l)

lock(l)
print x
unlock(l)


// Thread 2
lock(l)
x = 999
unlock(l)
```

Now, all data races in this example are gone, but a race condition still exists. The critical sections (the code segment between a pair of lock and unlock) are still unsequenced. The code can still be buggy, say if printing out “999” is undesirable.

### Benign or non-benign? Where lies the evilness?

Let’s suppose printing out “999” is indeed a buggy behavior.

Clearly, the buggy printing of “999” is not introduced by the data race but the race condition. To get rid of the bug, we can either _a)_ join thread 2 before the write operation to `x` in thread 1; or _b)_ put the two operations on `x` in thread 1 into the same critical section. Both fixes ensure there could be no unexpected operation between `x = 1` and `print x`.

Now One observation you might have is, fixing data races does not necessarily eliminate the race conditions. If so, **what is the harm actually brought by a data race? Why we want to get rid of them?**

Before we step into the evil world of data races, let’s first take a step back to understand a concept: **“benign data race”**. There is a widely held and strong perception that data races are acceptable in certain contexts, and thus are commonly used in existing code.

This turns out to be very wrong. Not only are those benign data races technically incorrect and harmful, but new bugs may be introduced by future re-compilation if the code is meant to be portable.

I present some common C/C++ “benign” patterns from a [paper][hans-paper] by Hans-J. Boehm below, and briefly explain how those common patterns could go wrong:

[hans-paper]: https://www.usenix.org/legacy/event/hotpar11/tech/final_files/Boehm.pdf

1. _Double-checked locking_

```C
if (!init_flag) {
    lock(); 
    if (!init_flag) {
        my_data = ...;
        init_flag = true;
    }
    unlock(); 
} 
tmp = my_data;
```

This is a very famous pattern (known as DCLP), and is also well-known to be incorrect. The code is potentially buggy if compiler optimization or hardware reordering is applied (which they are, in most real cases).

For example, there’s nothing to prevent the compiler from advancing `init_flag = true` before the setting of `my_data`. Assuming there are two threads executing the code above, the second thread may end up reading an uninitialized value (because `init_flag` is set to `true` before `my_data` get initialized).

A general solution for this pattern does not exist until Java 1.5 (the `volatile` keyword) and C++11 (the memory fence). Without these, we have to protect the whole pattern with a lock, which in turn brings a performance degradation.

For more details about DCLP, you can check the [wiki][dclp-wiki], this [page][java-dclp] for Java, and Scott and Andrei’s [paper][cpp-dclp] about C++.

[dclp-wiki]: https://en.wikipedia.org/wiki/Double-checked_locking
[java-dclp]: http://www.cs.umd.edu/~pugh/java/memoryModel/DoubleCheckedLocking.html
[cpp-dclp]: https://www.aristeia.com/Papers/DDJ_Jul_Aug_2004_revised.pdf

2. _Reading imprecise value is allowed_

There are cases where a read from a thread does not care about if another thread has updated the value or not, i.e., either the old value or the new value results in a valid computation. In such cases, are data races benign?

The answer, of course, is **NO**. Simply because data races will potentially cause the read operation to obtain a meaningless value that doesn’t correspond to either the old value nor the new value.

```C
// Read global
int my_counter = counter;
int (* my_func) (int);
if (my_counter > my_old_counter) {
    ...
    my_func = ...;
}
...
if (my_counter > my_old_counter) {
    ... 
    my_func(...) 
}
```

Consider the code pattern on the above, where `my_counter` reads from a global variable `counter` without protection. The global counter may get updated by some other threads running in parallel. Here the developer may think reading an old value of counter is fine due to the if `(my_counter > my_old_counter)` check.

However, if the compiler thinks the register of `my_counter` needs to be spilled between the two if-checks, then it is legit to re-read `my_counter`‘s value again to avoid spilling, as shown on the below. Now under this optimized code, the two if-checks may not yield the same result, which can lead to unexpected behavior when calling `my_func`.

```C
// Read global
int my_counter = counter;
int (* my_func) (int);
if (my_counter > my_old_counter) {
    ...
    my_func = ...;
}
...
// ANOTHER read global
int my_counter = counter;
if (my_counter > my_old_counter) {
    ... 
    my_func(...) 
}
```

If we go a bit further to the hardware level. Assuming we want to maintain an imprecise global 64-bit integer `counter`. We make the `counter++` concurrent and unprotected. If your system only supports 32-bit indivisible writes, then once a thread is updating the counter value from `2^32 - 1` to `2^32`, another thread could read a value whose higher bits are already updated but lower bits are not. This will make the counter value totally meaningless.

3. _Incorrect ad hoc synchronizations_

Ad hoc (or user constructed) synchronizations should not use ordinary operations. Otherwise, we will generally face issues similar to what is mentioned above.

```C
// `flag` is intended to be an ad hoc lock
while (!flag) {
    ...
}
```


```C
// compiler optimized code
tmp = flag
while (!tmp) {
    ...
}
```

For example, the busy-waiting loop above can be optimized to something like the second code snippet, due to register spilling. The optimized loop might run indefinitely under concurrent execution, yet it is equivalent to the example on top under sequential code.

Or if we want to use a busy-waiting loop as a memory barrier, like the example below:

```C
while (!flag) {}; // waiting for `data` to be updated
tmp = data;
```

Compiler or hardware could potentially reverse the order of the two instructions. Thus, this ad hoc memory barrier is mostly meaningless.

4. _Redundant write_

Assume we have a function f(x):

```C
// count is a shared variable between threads
f(x) {
    ...;
    for (p = x; p != 0; p = p -> next) {
        if (p->data < 0) count++;
    }
}
```

Notice that count is a shared variable, and it’s only updated when p has negative value. Now if we use this function in the following way:

```C
// Thread 1
count = 0;
f(positives);

// Thread 2
f(positives);
count = 0;
```

The argument `positives` is a linked list whose nodes only contain positive value. Hence, there’s only one data race between the two `count = 0` instructions. You may wonder, how could this possibly go wrong, since all we are doing is writing the same value to count repeatedly.

However, things become different if the compiler inlines `f(positives)` and promote the variable count to a thread-local register (this is legitimate because count is written unconditionally). Now the actual instructions being executed by each thread become something like below:

```C
// Thread 1
count = 0; // step 2
reg1 = count // step 4
count = reg1 // step 6

// Thread 2
reg2 = count; // step 1
count = reg2; // step 3
count = 0; // step 5
```

Now under this specific interleaving, we find it is possible for count to remain its original value instead of being zeroed out.

5. _Disjoint bit manipulation_

This kind of “benign” data races are [described][disjoint-bit] as:

> ... data races between two memory operations where the programmer knows for sure that the two operations use or modify different bits in a shared variable.

[disjoint-bit]: https://cseweb.ucsd.edu/~calder/papers/PLDI-07-DataRace.pdf

Those kinds of manipulation are not generally benign. Updating bits usually contains _a)_ Reading the whole value; _b)_ Updating the relevant bits; and _c)_ Writing the value back. We can clearly see specific interleaving may cause some updates to be invalid.

Even in the case when there is only 1 thread updating the bits, we can come up with the following example:

```C
x.bits1 = 1;
switch(i) {
    case 1:
        x.bits2 = 1;
        ...;
        break;
    case 2:
        x.bits2 = 1;
        ...;
        break;
    case 3:
        ...;
        break;
    default:
        x.bits2 = 1;
        ...;
        break;
}
```

Our original code is shown above. `x` is a global variable whose bits represent different flags, and `bits1` and `bits2` are two bit fields of `x`.

Notice that in our original code, `case 3` does not update `x.bits2` and it happens to be the branch we are using (assume this is a fact compiler does not know, so that the other branches will not be pruned). Now if we have a second thread only reading the value of `x.bits2`. This seems to be a perfectly safe situation.

However, existing compilers may consider adjacent bit-fields as belonging to the same memory location (here in our case, `x.bits1` and `x.bits2`). The write to `x.bits1` will make the compiler think the target memory location is data-race free, thus justify its optimizations on `x.bits2`. This leads to the optimized code shown on below, where the potential updates on `x.bits2` are advanced to shrink the code size (if we have more branches that update `x.bits2`). Now if we are still using `case 3`, the read from other thread will conflict with the write on `case 3`, causing the second thread to read invalid values of `x.bits2`.

```C
x.bits1 = 1;
tmp = x.bits2
x.bits2 =1
switch(i) {
    case 1:
        ...;
        break;
    case 2:
        ...;
        break;
    case 3:
        x.bits2 = tmp;
        ...;
        break;
    default:
        ...;
        break;
}
```

**To sum up**, the evilness of data races mostly lies in compiler optimizations, hardware reordering, and underlying memory models. Most compiler optimizations assume the program is data-race free, thus compilers may introduce **undefined behaviors** when data races exist. The worst thing about undefined behavior is it could lead to any actions (such as launching a missile?) instead of just entering an invalid path of your program.

If you are interested in reading more discussion related to data races, there’s another [blog][benign-data-race] explaining this.

[benign-data-race]: https://software.intel.com/content/www/us/en/develop/blogs/benign-data-races-what-could-possibly-go-wrong.html

### How do I prevent my program from launching missiles unexpectedly?

If you make it here, hopefully you are not terrified by what can be caused by data races. Just to be fair, there could be “benign” data races under more concrete contexts, such as knowing the specific architecture, compiler version, optimization passes used and the memory models, and the code is not intended to be portable.

Nevertheless, I strongly believe developers should pay more attention to potential data races just like how they treat compiler warnings (I feel terribly sorry for you if you don't).

Properly protecting concurrent shared memory accesses not only prevent programs from all those subtle bugs we presented above, but also significantly increase the readability for your code by specifying their concurrent semantics. Besides, there are tools like [ThreadSanitizer][tsan], [Intel Inspector][inspector], and [Coderrect Racedetector][coderrect] to efficiently reveal potential data races at different programming phases.

Let’s just not making our software program to be a missile launcher, :=).

[tsan]: https://clang.llvm.org/docs/ThreadSanitizer.html
[inspector]: https://software.intel.com/content/www/us/en/develop/tools/inspector.html
[coderrect]: https://coderrect.com/

