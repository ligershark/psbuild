namespace PSBuild {
    using Microsoft.Build.Framework;
    using System;

    public class ExecutionInfo : PSBuild.IExecutionInfo {
        public ExecutionInfo() { }
        public ExecutionInfo(string name, BuildStatusEventArgs startedArgs, BuildStatusEventArgs finishedArgs) {
            this.Name = name;
            this.StartedArgs = startedArgs;
            this.FinishedArgs = finishedArgs;
            this.TimeSpent = finishedArgs.Timestamp.Subtract(startedArgs.Timestamp);
        }
        public string Name { get; set; }
        public TimeSpan TimeSpent { get; set; }
        public BuildStatusEventArgs StartedArgs { get; set; }
        public BuildStatusEventArgs FinishedArgs { get; set; }
    }

    public interface IExecutionInfo {
        string Name { get; set; }
        TimeSpan TimeSpent { get; set; }
    }
}
