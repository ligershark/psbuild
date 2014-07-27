namespace PSBuild {
    using Microsoft.Build.Framework;
    using System;

    public class ExecutionInfo : PSBuild.IExecutionInfo {
        public ExecutionInfo() { }
        public ExecutionInfo(string name, BuildStatusEventArgs startedArgs, BuildStatusEventArgs finishedArgs) {
            this.Name = name;
            this.TimeSpent = finishedArgs.Timestamp.Subtract(startedArgs.Timestamp);
        }
        public string Name { get; set; }
        public TimeSpan TimeSpent { get; set; }
    }

    public interface IExecutionInfo {
        string Name { get; set; }
        TimeSpan TimeSpent { get; set; }
    }
}
