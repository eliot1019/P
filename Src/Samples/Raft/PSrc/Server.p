// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License (MIT). See License.txt in the repo root for license information.
// ------------------------------------------------------------------------------------------------

// using System;
// using System.Collections.Generic;
// using System.Linq;
// using System.Text;
// using System.Threading.Tasks;

// namespace Raft
// {

machine Server
{
    var ServerId : int;
    var ClusterManager : machine;
    var Servers: seq[machine];
    var LeaderId: machine;
    var ElectionTimer: machine;
    var PeriodicTimer: machine;
    var CurrentTerm: int;
    var VotedFor: machine;
    var Logs: seq[Log];
    var CommitIndex: int;
    var LastApplied: int;
    var NextIndex: map[machine, int];
    var MatchIndex: map[machine, int];
    var VotesReceived: int;
    var LastClientRequest: (Client: machine, Command: int);
    var i: int;

    start state Init
    {
        entry
        {
            i = 0;
            CurrentTerm = 0;
            LeaderId = default(machine);
            VotedFor = default(machine);
            Logs = default(seq[Log]);
            CommitIndex = 0;
            LastApplied = 0;
            NextIndex = default(map[machine, int]);
            MatchIndex = default(map[machine, int]);
        }

        /*
            @Receive: Configuration payload from ClusterManager. 
        */
        on SConfigureEvent do (payload: (Id: int, Servers: seq[machine], ClusterManager: machine)) {
            configServer(payload);            
        }
        on BecomeFollower goto Follower;
        on BecomeLeader goto Leader;
        defer VoteRequest, AppendEntriesRequest;
    }

    fun configServer(payload: (Id: int, Servers: seq[machine], ClusterManager: machine)){
            ServerId = payload.Id;
            Servers = payload.Servers;
            ClusterManager = payload.ClusterManager;

            // ElectionTimer = new ElectionTimer();
            // send ElectionTimer, EConfigureEvent, this;

            // PeriodicTimer = new PeriodicTimer();
            // send PeriodicTimer, PConfigureEvent, this;
            if (payload.Id == 0){
                raise BecomeLeader;
            } else {
                raise BecomeFollower;
            }     
        }

    state Follower
    {
        entry
        {
            print "[Follower] {0} onEntry", this;
            LeaderId = default(machine);
            VotesReceived = 0;

            // send ElectionTimer, EStartTimer;
        }

        on Request do (payload: (Client: machine, Command: int)) {
            if (LeaderId != null)
            {
                print "[Follower | Request] {0} sends request to Leader {1}", this, LeaderId;
                send LeaderId, Request, payload.Client, payload.Command;
            }
            else
            {
                print "[Follower | Request] {0} no Leader, redirect to ClusterManager.", this;
                send ClusterManager, RedirectRequest, payload;
            }
        }
        on VoteRequest do (payload: (Term: int, CandidateId: machine, LastLogIndex: int, LastLogTerm: int)) {
            print "[Follower | VoteRequest] Server {0} | Payload Term {1} | Current Term {2}", this, payload.Term, CurrentTerm;
            if (payload.Term > CurrentTerm)
            {
                CurrentTerm = payload.Term;
                VotedFor = default(machine);
            }

            Vote(payload);
        }

        // TODO: see if this ever shows up. It doesn't really make sense for a follower to receive a vote response
        on VoteResponse do (request: (Term: int, VoteGranted: bool)) {
            print "[Follower | VoteResponse] Server {0} | Payload Term {1} | Current Term {2}", this, request.Term, CurrentTerm;
            if (request.Term > CurrentTerm)
            {
                CurrentTerm = request.Term;
                VotedFor = default(machine);
            }
        }

        // TODO: see if this ever shows up. It doesn't really make sense for a follower to receive an append entries response
        on AppendEntriesRequest do (request: (Term: int, LeaderId: machine, PrevLogIndex: int, 
            PrevLogTerm: int, Entries: seq[Log], LeaderCommit: int, ReceiverEndpoint: machine)){
            print "[Follower | AppendEntriesRequest] Server {0}", this;
            if (request.Term > CurrentTerm)
            {
                CurrentTerm = request.Term;
                VotedFor = default(machine);
            }

            AppendEntries(request);
        }

        on AppendEntriesResponse do (request: (Term: int, Success: bool, Server: machine,
         ReceiverEndpoint: machine)){
            print "[Follower | AppendEntriesResponse] Server {0}", this;
            if (request.Term > CurrentTerm)
            {
                CurrentTerm = request.Term;
                VotedFor = default(machine);
            }
        }
        on ETimeout do {
            raise BecomeCandidate;
        }
        on ShutDown do { 
            ShuttingDown();
        }
        on BecomeFollower goto Follower;
        on BecomeCandidate goto Candidate;
        ignore PTimeout;
    }


    state Candidate
    {
        entry
        {
            CurrentTerm = CurrentTerm + 1;
            VotedFor = this;
            VotesReceived = 1;

            // send ElectionTimer, EStartTimer;

            //Logger.WriteLine("\n [Candidate] " + this.ServerId + " | term " + this.CurrentTerm + " | election votes " + this.VotesReceived + " | log " + this.Logs.Count + "\n");
            print "\n [Candidate] {0} on Entry | Term {1} | Votes Received {2} | Log # entries: {3}\n", this, CurrentTerm, VotesReceived, sizeof(Logs); 

            BroadcastVoteRequests();
        }

        on Request do (payload: (Client: machine, Command: int)) {
            // this should be throwing an error?
            if (LeaderId != null)
            {
                print "[Candidate | Request] {0} sends request to Leader {1}", this, LeaderId;
                send LeaderId, Request, payload.Client, payload.Command;
            }
            else
            {
                print "[Candidate | Request] {0} no leader, redirect to ClusterManager", this;
                send ClusterManager, RedirectRequest, payload;
            }
        }
        
        on VoteRequest do (request: (Term: int, CandidateId: machine, LastLogIndex: int, LastLogTerm: int)){
            print "[Candidate | VoteRequest] Server {0} | Payload Term {1} | Current Term {2}", this, request.Term, CurrentTerm;
            if (request.Term > CurrentTerm)
            {
                CurrentTerm = request.Term;
                VotedFor = default(machine);
                // Vote(request);
                // TODO: Check if bugs out due to above commenting-out
                raise BecomeFollower;
            }
            else
            {
                // We shouldn't be voting here since we already voted for ourself
                // Vote(request);
            }
        }

        on VoteResponse do (request: (Term: int, VoteGranted: bool)) {
            print "[Candidate | VoteResponse] Server {0} | Payload Term {1} | Current Term {2}", this, request.Term, CurrentTerm;
            if (request.Term > CurrentTerm)
            {
                CurrentTerm = request.Term;
                VotedFor = default(machine);
                raise BecomeFollower;
            }
            else if (request.Term != CurrentTerm)
            {
            }

            else if (request.VoteGranted)
            {
                VotesReceived = VotesReceived + 1;
                if (VotesReceived >= (sizeof(Servers) / 2) + 1)
                {
                   // this.Logger.WriteLine("\n [Leader] " + this.ServerId + " | term " + this.CurrentTerm +
                    //    " | election votes " + this.VotesReceived + " | log " + this.Logs.Count + "\n");
                    print "\n [Leader] {0} | term {1} | election votes {2} | log {3}\n", this, CurrentTerm, VotesReceived, sizeof(Logs); 
                    VotesReceived = 0;
                    raise BecomeLeader;
                }
            }
        }
        // TODO: Confirm that commenting out AppendEntries below is correct
        on AppendEntriesRequest do (request: (Term: int, LeaderId: machine, PrevLogIndex: int, PrevLogTerm: int,
         Entries: seq[Log], LeaderCommit: int, ReceiverEndpoint: machine)) {
            print "[Candidate | AppendEntriesRequest] Server {0}", this;
            if (request.Term > CurrentTerm)
            {
                CurrentTerm = request.Term;
                VotedFor = default(machine);
                // AppendEntries(request);
                raise BecomeFollower;
            }
            else
            {
                // AppendEntries(request);
            }
        }
        on AppendEntriesResponse do (request: (Term: int, Success: bool, Server: machine, ReceiverEndpoint: machine)) {
            print "[Candidate | AppendEntriesResponse] Server {0}", this;
            RespondAppendEntriesAsCandidate(request);
        }
        on ETimeout do {
            raise BecomeCandidate;
        }
        on PTimeout do BroadcastVoteRequests;
        on ShutDown do ShuttingDown;
        on BecomeLeader goto Leader;
        on BecomeFollower goto Follower;
        on BecomeCandidate goto Candidate;
    }

    fun BroadcastVoteRequests()
    {
        // BUG: duplicate votes from same follower
        var idx: int;
        var lastLogIndex: int;
        var lastLogTerm: int; 

        // send PeriodicTimer, PStartTimer;
        idx = 0;
        while (idx < sizeof(Servers)) {
           if (idx == ServerId) {
               idx = idx + 1;
                continue;
           }
            lastLogIndex = sizeof(Logs) - 1;
            lastLogTerm = GetLogTermForIndex(lastLogIndex);

            print "Sending VoteRequest from Server {0} to Server {1}", this, Servers[idx];
            send Servers[idx], VoteRequest, (Term=CurrentTerm, CandidateId=this, LastLogIndex=lastLogIndex, LastLogTerm=lastLogTerm);
            idx = idx + 1;
        }
    }

    fun RespondAppendEntriesAsCandidate(request: (Term: int, Success: bool, Server: machine, ReceiverEndpoint: machine))
    {
        if (request.Term > CurrentTerm)
        {
            CurrentTerm = request.Term;
            VotedFor = default(machine);
            raise BecomeFollower;
        }
    }

    state Leader
    {
        entry
        {
            var logIndex: int;
            var logTerm: int;
            var idx: int;

            CommitIndex = 0;                                                                              

            announce EMonitorInit, (NotifyLeaderElected, CurrentTerm);
            //monitor<SafetyMonitor>(NotifyLeaderElected, CurrentTerm);
            send ClusterManager, NotifyLeaderUpdate, (Leader=this, Term=CurrentTerm);

            logIndex = sizeof(Logs) - 1;
            logTerm = GetLogTermForIndex(logIndex);

            //this.NextIndex.Clear();
            //this.MatchIndex.Clear();
            NextIndex = default(map[machine, int]);
            MatchIndex = default(map[machine, int]);
            
            idx = 0;
            while (idx < sizeof(Servers))
            {
                if (idx == ServerId) {
                    idx = idx + 1;
                    continue;
                }
                
                NextIndex[Servers[idx]] = logIndex + 1;
                MatchIndex[Servers[idx]] = 0;
                idx = idx + 1;
            }

            idx = 0;
            while (idx < sizeof(Servers))
            {
                print "[Leader | Entry] {0} Heartbeat appendEntryRequest to {1}", this, idx;
                if (idx == ServerId){
                    idx = idx + 1;
                    continue;
                }
                send Servers[idx], AppendEntriesRequest, 
                    (Term=CurrentTerm, LeaderId=this, PrevLogIndex=logIndex, PrevLogTerm=logTerm, Entries=default(seq[Log]), LeaderCommit=CommitIndex, ReceiverEndpoint=default(machine));
                idx = idx + 1;
            }
        }

        on Request do (request: (Client: machine, Command: int)) {
            ProcessClientRequest(request);
        }
        on VoteRequest do (request: (Term: int, CandidateId: machine, LastLogIndex: int, LastLogTerm: int)) {
            VoteAsLeader(request);
        }
        on VoteResponse do (request: (Term: int, VoteGranted: bool)) {
            RespondVoteAsLeader(request);
        }
        on AppendEntriesRequest do (request: (Term: int, LeaderId: machine, PrevLogIndex: int, 
            PrevLogTerm: int, Entries: seq[Log], LeaderCommit: int, ReceiverEndpoint: machine)) {
            AppendEntriesAsLeader(request);
        }
        on AppendEntriesResponse do (request: (Term: int, Success: bool, Server: machine, ReceiverEndpoint: machine)) {
            RespondAppendEntriesAsLeader(request);
        }
        on ShutDown do ShuttingDown;
        on BecomeFollower goto Follower;
        ignore ETimeout, PTimeout;
    }

    // TODO: This needs to be replaced with proper heartbeat response
    fun ProcessClientRequest(trigger: (Client: machine, Command: int))
    {
        var log: Log;
        var print_idx: int;
        print "[Leader | Request] Leader {0} processing Client {1}", this, trigger.Client;
        LastClientRequest = trigger;
        log = default(Log);
        log.Term = CurrentTerm;
        log.Command = LastClientRequest.Command;
        print "[Leader | Request] Log Term: {0}, Log Command: {1}, idx: {2}", log.Term, log.Command, i;
        Logs += (i, log);
        print "[Leader | Request] Num entries: {0}, i: {1}", sizeof(Logs), i;
        i = i + 1;
        print_idx = 0;
        while (print_idx < i){
            print "[Leader | Request] Log element {0}: {1}", print_idx, Logs[print_idx];
            print_idx = print_idx + 1;
        }

        BroadcastLastClientRequest();
    }

    fun BroadcastLastClientRequest()
    {
        //this.Logger.WriteLine("\n [Leader] " + this.ServerId + " sends append requests | term " +
            //this.CurrentTerm + " | log " + this.Logs.Count + "\n");
        var lastLogIndex: int;
        var serverIndex: int;
        var idx2: int;
        var prevLogIndex: int;
        var prevLogTerm: int;
        var server: machine;
        var logsAppend: seq[Log];
        print "\n[Leader | PCR | BroadcastLastClientReq] [Leader] {0} sends append requests | term {1} | log {2}\n", this, CurrentTerm, sizeof(Logs);

        lastLogIndex = sizeof(Logs) - 1;
        while (serverIndex < sizeof(Servers))
        {
            if (serverIndex == ServerId) {
                serverIndex = serverIndex + 1;
                continue;
            }
            server = Servers[serverIndex];
            print "[Leader | PCR | BroadcastLastClientReq] Next index: {0}", NextIndex[server];
            if (lastLogIndex < NextIndex[server]) {
                serverIndex = serverIndex + 1;
                continue;
            }

            logsAppend = default(seq[Log]);

            // idx2 = NextIndex[server];
            // while (idx2 < sizeof(Logs)) {
            //     print "[Leader | PCR | BroadcastLastClientReq] Appending to log";
            //     logsAppend += (idx2 - (NextIndex[server] - 1), Logs[idx2]);
            //     idx2 = idx2 + 1;
            // }

            // TODO: changed to i - 1
            logsAppend += (i - 1, Logs[i - 1]);

            // TODO: MAKE SURE TO UPDATE TO HEARTBEAT IMPLEMENTATION

            print "Before prevLogIndex";
            prevLogIndex = NextIndex[server] - 1;
            print "After prevLogIndex";
            prevLogTerm = GetLogTermForIndex(prevLogIndex);
            print "[Leader | PCR | BroadcastLastClientReq] {0} appendEntryRequest to {1}", this, serverIndex;
            send server, AppendEntriesRequest, (Term=CurrentTerm, LeaderId=this, PrevLogIndex=prevLogIndex,
                PrevLogTerm=prevLogTerm, Entries=logsAppend, LeaderCommit=CommitIndex, ReceiverEndpoint=LastClientRequest.Client);
            serverIndex = serverIndex + 1;
        }
    }

    fun VoteAsLeader(request: (Term: int, CandidateId: machine, LastLogIndex: int, LastLogTerm: int))
    {
        if (request.Term > CurrentTerm)
        {
            print "[Leader | VoteAsLeader] Leader {0} term {1} behind request term {2}.", this, CurrentTerm, request.Term;
            CurrentTerm = request.Term;
            VotedFor = default(machine);

            RedirectLastClientRequestToClusterManager();

            // TODO: commented below
            // Vote(request);

            raise BecomeFollower;
        }
        else
        {
            // Vote(request);
        }
    }

    fun RespondVoteAsLeader(request: (Term: int, VoteGranted: bool))
    {
        if (request.Term > CurrentTerm)
        {
            CurrentTerm = request.Term;
            VotedFor = default(machine);

            RedirectLastClientRequestToClusterManager();
            raise BecomeFollower;
        }
    }

    fun AppendEntriesAsLeader(request: (Term: int, LeaderId: machine, PrevLogIndex: int, PrevLogTerm: int, Entries: seq[Log], LeaderCommit: int, ReceiverEndpoint: machine))
    {
        if (request.Term > CurrentTerm)
        {
            CurrentTerm = request.Term;
            VotedFor = default(machine);

            RedirectLastClientRequestToClusterManager();

            // TODO: commented out below
            // AppendEntries(request);

            raise BecomeFollower;
        }
    }

    fun RespondAppendEntriesAsLeader(request: (Term: int, Success: bool, Server: machine, ReceiverEndpoint: machine))
    {
        var commitIndex: int;
        var logsAppend: seq[Log];
        var prevLogIndex: int;
        var prevLogTerm: int; 
        var idx: int;
        print "[Leader | AppendEntriesResponse] {0} received response {1} from server {2}", this, request.Success, request.Server; 
        print "[Leader | AppendEntriesResponse] Leader term: {0}, follower term: {1}", CurrentTerm, request.Term;
        if (request.Term > CurrentTerm)
        {
            CurrentTerm = request.Term;
            VotedFor = default(machine);

            RedirectLastClientRequestToClusterManager();
            raise BecomeFollower;
        }
        else if (request.Term != CurrentTerm)
        {
        }

        // TODO: check final bullet point of "Rules for servers" in paper
        else if (request.Success)
        {
            print "[Leader | AppendEntriesResponse] Success; preparing commit.";
            print "[Leader | AppendEntriesResponse] NextIndex: {0}, MatchIndex: {1}", NextIndex[request.Server], MatchIndex[request.Server];
            NextIndex[request.Server] = sizeof(Logs);
            MatchIndex[request.Server] = sizeof(Logs) - 1;
            print "[Leader | AppendEntriesResponse] NextIndex: {0}, MatchIndex: {1}", NextIndex[request.Server], MatchIndex[request.Server];
            
            VotesReceived = VotesReceived + 1;
            print "[Leader | AppendEntriesResponse] VotesReceived: {0}", VotesReceived;
            if (request.ReceiverEndpoint == null){
                print "[Leader | AppendEntriesResponse] request.ReceiverEndpoint: null";    
            }        
            if (request.ReceiverEndpoint != null &&
                VotesReceived >= ((sizeof(Servers)-1) / 2) + 1)
            {
                //this.Logger.WriteLine("\n [Leader] " + this.ServerId + " | term " + this.CurrentTerm +
                  //  " | append votes " + this.VotesReceived + " | append success\n");
                print "\n[Leader] {0} | term {1} | append votes {2} | append success\n", this, CurrentTerm, VotesReceived; 
                commitIndex = MatchIndex[request.Server];
                if (commitIndex > CommitIndex &&
                    Logs[commitIndex - 1].Term == CurrentTerm)
                {
                    CommitIndex = commitIndex;

                   // this.Logger.WriteLine("\n [Leader] " + this.ServerId + " | term " + this.CurrentTerm + " | log " + this.Logs.Count + " | command " + this.Logs[commitIndex - 1].Command + "\n");
                    print "\n[Leader] {0} | term {1} | log {2} | command {3}\n", this, CurrentTerm, sizeof(Logs), Logs[commitIndex - 1].Command; 

                }

                VotesReceived = 0;
                LastClientRequest = (Client=default(machine), Command=default(int));

                send request.ReceiverEndpoint, Response;
            }
        }
        else
        {
            if (NextIndex[request.Server] > 1)
            {
                NextIndex[request.Server] = NextIndex[request.Server] - 1;
            }

//            List<Log> logs = this.Logs.GetRange(this.NextIndex[request.Server] - 1, this.Logs.Count - (this.NextIndex[request.Server] - 1));
            logsAppend = default(seq[Log]);
            idx = NextIndex[request.Server] - 1;
            while (idx < sizeof(Logs)) {
                logsAppend += (idx, Logs[idx]);
                idx = idx + 1;
            }

            prevLogIndex = NextIndex[request.Server] - 1;
            prevLogTerm = GetLogTermForIndex(prevLogIndex);

            //this.Logger.WriteLine("\n [Leader] " + this.ServerId + " | term " + this.CurrentTerm + " | log " + this.Logs.Count + " | append votes " + this.VotesReceived + " | append fail (next idx = " + this.NextIndex[request.Server] + ")\n");
            print "\n[Leader] {0} | term {1} | log {2} | append votes {3} | append fail (next idx = {4})\n", this, CurrentTerm, sizeof(Logs), VotesReceived, NextIndex[request.Server];
            send request.Server, AppendEntriesRequest, (Term=CurrentTerm, LeaderId=this, PrevLogIndex=prevLogIndex,
                PrevLogTerm=prevLogTerm, Entries=Logs, LeaderCommit=CommitIndex, ReceiverEndpoint=request.ReceiverEndpoint);
        }
    }

    fun Vote(request: (Term: int, CandidateId: machine, LastLogIndex: int, LastLogTerm: int))
    {
        var lastLogIndex: int;
        var lastLogTerm: int;
        lastLogIndex = sizeof(Logs) - 1;
        lastLogTerm = GetLogTermForIndex(lastLogIndex);

        if (request.Term < CurrentTerm ||
            (VotedFor != default(machine) && VotedFor != request.CandidateId) ||
            lastLogIndex > request.LastLogIndex ||
            lastLogTerm > request.LastLogTerm)
        {
            //this.Logger.WriteLine("\n [Server] " + this.ServerId + " | term " + this.CurrentTerm +
              //  " | log " + this.Logs.Count + " | vote false\n");
            print "\n [Server] {0} | term {1} | log {2} | Reject {3}", ServerId, CurrentTerm, sizeof(Logs), request.CandidateId;
            send request.CandidateId, VoteResponse, (Term=CurrentTerm, VoteGranted=false);
        }
        else
        {
            //this.Logger.WriteLine("\n [Server] " + this.ServerId + " | term " + this.CurrentTerm +
               // " | log " + this.Logs.Count + " | vote true\n");
            print "\n [Server] {0} | term {1} | log {2} | Approve {3}", ServerId, CurrentTerm, sizeof(Logs), request.CandidateId;

            VotedFor = request.CandidateId;
            LeaderId = default(machine);

            send request.CandidateId, VoteResponse, (Term=CurrentTerm, VoteGranted=true);
        }
    }

    fun AppendEntries(request: (Term: int, LeaderId: machine, PrevLogIndex: int, PrevLogTerm: int, Entries: seq[Log], LeaderCommit: int, ReceiverEndpoint: machine))
    {
        var startIndex: int;
        var idx: int;
        var decIdx: int;
        var logEntry: Log;

        if (request.Term < CurrentTerm)
        {
            // AppendEntries RPC #2
            print "\n[Server] {0} | term {1} | log {2} | last applied {3} | append false (<term) \n", this, CurrentTerm, sizeof(Logs), LastApplied;
            send request.LeaderId, AppendEntriesResponse, (Term=CurrentTerm, Success=false, Server=this, ReceiverEndpoint=request.ReceiverEndpoint);
        }
        else
        {
            // AppendEntries RPC #2
            if (request.PrevLogIndex > 0 &&
                (sizeof(Logs) < request.PrevLogIndex ||
                Logs[request.PrevLogIndex - 1].Term != request.PrevLogTerm))
            {
                print "\n[Leader] {0} | term {1} | log {2} | last applied: {3} | append false (not in log)\n", this, CurrentTerm, sizeof(Logs), LastApplied; 
                send request.LeaderId, AppendEntriesResponse, (Term=CurrentTerm, Success=false, Server=this, ReceiverEndpoint=request.ReceiverEndpoint);
            }
            else
            {
                idx = 0;

                // AppendEntries RPC #3
                while (idx < sizeof(request.Entries) && 
                    (idx + request.PrevLogIndex + 1) < sizeof(Logs)){
                    if (Logs[idx + request.PrevLogIndex + 1] != request.Entries[idx]){
                        DeleteFromLog(idx + request.PrevLogIndex + 1, sizeof(Logs));
                        break;
                    }
                } 

                // AppendEntries RPC #4. Note we explicitly DO NOT reset idx.
                while (idx < sizeof(request.Entries)){
                    Logs += (idx + request.PrevLogIndex + 1, request.Entries[idx]);
                }

                // AppendEntries RPC #5. Index of last new entry is sizeof(Logs) - 1
                if (request.LeaderCommit > CommitIndex &&
                    (sizeof(Logs) - 1) < request.LeaderCommit)
                {
                    CommitIndex = sizeof(Logs) - 1;
                }
                else if (request.LeaderCommit > CommitIndex)
                {
                    CommitIndex = request.LeaderCommit;
                }

                if (CommitIndex > LastApplied)
                {
                    LastApplied = LastApplied + sizeof(request.Entries);
                }

                print "\n[Server] {0} | term {1} | log {2} | entries received {3} | last applied {4} | append true\n", this, CurrentTerm, sizeof(Logs), sizeof(request.Entries), LastApplied; 

                LeaderId = request.LeaderId;
                send request.LeaderId, AppendEntriesResponse, (Term=CurrentTerm, Success=true, Server=this, ReceiverEndpoint=request.ReceiverEndpoint);
            }
        }
    }

    /* Delete entries from class variable Logs, a seq<.
        @param start: Inclusive, first index to delete.
        @param end: Exclusive, delete up to but not including this index.
    */
    fun DeleteFromLog(startIndex: int, endIndex: int)
    {
        var idx: int;
        idx = endIndex - 1;
        while (idx >= startIndex){
            Logs -= idx;
        }
    }

    fun RedirectLastClientRequestToClusterManager()
    {
        if (LastClientRequest != null)
        {
            send ClusterManager, Request, (Client=LastClientRequest.Client, Command=LastClientRequest.Command);
        }
    }

    fun GetLogTermForIndex(logIndex: int) : int
    {
        var logTerm: int;
        logTerm = 0;
        print "LogIndex: {0}", logIndex;
        if (logIndex > 0)
        {
            logTerm = Logs[logIndex].Term;
        }

        return logTerm;
    }

    fun ShuttingDown()
    {
        // send ElectionTimer, halt;
        // send PeriodicTimer, halt;

        raise halt;
    }
}
// }

