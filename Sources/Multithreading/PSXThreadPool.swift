/// Copyright 2017 Sergei Egorov
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
/// http://www.apache.org/licenses/LICENSE-2.0
///
/// Unless required by applicable law or agreed to in writing, software
/// distributed under the License is distributed on an "AS IS" BASIS,
/// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
/// See the License for the specific language governing permissions and
/// limitations under the License.

import Foundation

public class PSXThreadPool {
    
    /// Scheduler for assign jobs between threads.
    fileprivate var scheduler: PSXScheduler?

    /// The worker threads.
    internal var workerThreads: [Int: PSXWorkerThread] = [:]

    /// The keys with which the user created threads.
    internal var userThreadsKeys: [AnyHashable: Int] = [:]

    /// Global jobs queue.
    internal var globalQueue = PSXJobQueue()

    /// Condition variable for get notification when all jobs from global queue are complete.
    internal var jobsHasFinished = PSXCondition()
    
    /// Mutex for waiting to complete all jobs from the global queue.
    internal var jobsMutex = PSXMutex()

    /// Mutex for get (alive,waiting, working) threads.
    internal var threadsMutex = PSXMutex()


    /// Prefix for threads name. 
    /// If creating PSXQueue, then it changes this value to its own name.
    internal var threadsNamePrefix = "pool"
    
    /// The status of waiting for the completion of all jobs from the global queue
    internal var waiting = false
    
    /// Returns alive worker threads in pool
    internal var aliveThreads: [PSXWorkerThread] {
        threadsMutex.lock()
        let alive = workerThreads.filter{ $0.value.status != .inactive }.map{ $0.value }
        threadsMutex.unlock()
        return alive
    }
    
    /// Returns the worker threads that are waiting for jobs
    internal var waitingThreads: [PSXWorkerThread] {
        threadsMutex.lock()
        let waiting = workerThreads.filter{ $0.value.status == .waiting }.map{ $0.value }
        threadsMutex.unlock()
        return waiting
    }
    
    /// Returns the worker threads that are currently working
    internal var workingThreads: [PSXWorkerThread] {
        threadsMutex.lock()
        let working = workerThreads.filter{ $0.value.status == .working }.map{ $0.value }
        threadsMutex.unlock()
        return working
    }
    
    /// Returns the default singleton instance.
    private static let _default = PSXThreadPool(count: 1)

    public class var `default`: PSXThreadPool {
        return _default
    }
    
    /// Initialization
    ///
    /// Parameter count: The number of threads with which the thread pool will be initialized.
    ///
    public convenience init(count: Int) {
        self.init()
        createThreads(count)
        while aliveThreads.count != count {}
        scheduler = PSXScheduler(forPool: self)
    }
    
    deinit {
        destroy()
    }
    
    /// Creates a certain number of threads.
    ///
    /// Parameter count: The number of threads to create.
    ///
    fileprivate func createThreads(_ count: Int) {
        for _ in 0 ..< count {
            createThread()
        }
    }
    
    /// Creates new thread.
    /// Returns the key of the created thread from the worker threads array.
    ///
    @discardableResult
    fileprivate func createThread() -> Int {
        let id = workerThreads.count
        let thread = PSXWorkerThread(pool: self, id: id)
        let name = "\(threadsNamePrefix)-psxthread-\(id)"
        thread.name = name
        workerThreads[id] = thread
        thread.start()
        return id
    }
    
    /// Creates new thread.
    ///
    @discardableResult
    public func newThread() -> PSXThread {
        let id = createThread()
        let thread = workerThreads[id]
        return thread!
    }
    
    /// Creates thread with specified key.
    ///
    /// Parameter key: The key with which the thread will be created.
    ///
    @discardableResult
    public func newThread(forKey key: AnyHashable) -> PSXThread {
        let id = createThread()
        userThreadsKeys[key] = id
        let thread = workerThreads[id]
        return thread!
    }
    
    /// Returns user thread, if exists. Otherwise returns nil.
    ///
    /// Parameter key: The key with which the thread is associated.
    ///
    public func getThread(forKey key: AnyHashable) -> PSXThread? {
        guard let id = userThreadsKeys[key], let thread = workerThreads[id] else {
            return nil
        }
        return thread
    }
    
    /// Destroys user thread, if exists.
    ///
    /// Parameter key: The key with which the thread is associated.
    ///
    public func destroyThread(forKey key: AnyHashable) {
        guard let id = userThreadsKeys[key], let thread = workerThreads.removeValue(forKey: id) else {
            return
        }
        thread.exit()
    }
    
    /// Adds job to the thread pool.
    ///
    /// - Parameters:
    ///   - function: Function that will be performed.
    ///   - argument: Function's argument.
    ///
    public func addJob(function: @escaping (UnsafeMutableRawPointer?) -> Void, argument: UnsafeMutableRawPointer?) {
        let newJob = PSXJob(function: function, arg: argument)
        globalQueue.put(newJob: newJob)
    }
    
    /// Adds job to the thread pool.
    ///
    /// - Parameter block: A block of code that will be performed.
    ///
    public func addJob(_ block: @escaping () -> Void) {
        let job = PSXJob(block: block)
        globalQueue.put(newJob: job)
    }
    
    /// Waits until all jobs from global queue have finished.
    ///
    public func wait() {
        jobsMutex.lock()
        waiting = true
        while globalQueue.jobsCount > 0 || workingThreads.count > 0 {
            jobsHasFinished.wait(mutex: jobsMutex)
        }
        waiting = false
        jobsMutex.unlock()
    }
    
    /// Terminates all worker threads, and scheduler threads.
    ///
    internal func destroy() {
        for worker in workerThreads {
            worker.value.exit()
        }
        if let sh = scheduler {
            sh.destroy()
        }
    }
    
    func pause() {
        /// Unimplemented
    }
    
    func resume() {
        /// Unimplemented
    }
    
}