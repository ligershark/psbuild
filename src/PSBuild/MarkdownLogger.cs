namespace PSBuild {
    using System.Text;
    using Microsoft.Build.Framework;
    using MarkdownLog;
    using System.Linq;
    using System.Collections.Generic;
    using System;
    using System.Collections;
    using Microsoft.Build.Utilities;
    using PSBuild.Extensions;
    using System.IO;
    /// <summary>
    /// This class is simply for demonstration purposes, a better file logger to use is the
    /// Microsoft.Build.Engine.FileLogger class.
    /// 
    /// Author: Sayed Ibrahim Hashimi (sayed.hashimi@gmail.com)
    /// This class has not been throughly tested and is offered with no warranty.
    /// copyright Sayed Ibrahim Hashimi 2005
    /// </summary>
    public class MarkdownLogger : BaseLogger {
        #region Fields
        private StringBuilder _messages;
        private List<ExecutionInfo> _projectsExecuted;
        private Dictionary<string, ExecutionInfo> _projectsExecutedMap;
        private Stack<BuildStatusEventArgs> _projectsStarted;
        private List<IMarkdownElement> _projectSummary;

        private Dictionary<string, ExecutionInfo> _targetsExecuted;
        private Stack<TargetStartedEventArgs> _targetsStarted;

        private Dictionary<string, ExecutionInfo> _taskExecuted;
        private Stack<TaskStartedEventArgs> _tasksStarted;
        #endregion

        public MarkdownLogger() {
            MdElements = new List<IMarkdownElement>();
            this._targetsExecuted = new Dictionary<string, ExecutionInfo>();
            this._targetsStarted = new Stack<TargetStartedEventArgs>();

            this._taskExecuted = new Dictionary<string, ExecutionInfo>();
            this._tasksStarted = new Stack<TaskStartedEventArgs>();

            this._projectSummary = new List<IMarkdownElement>();
            this._projectsExecuted = new List<ExecutionInfo>();
            this._projectsExecutedMap = new Dictionary<string, ExecutionInfo>();
            this._projectsStarted = new Stack<BuildStatusEventArgs>();
        }

        private List<IMarkdownElement> MdElements { get; set; }
        #region ILogger Members
        public override void Initialize(IEventSource eventSource) {
            base.Initialize(eventSource);
            Filename = "build.log.md";
            _messages = new StringBuilder();

            this.InitializeParameters();
            
            //Register for the events here
            eventSource.BuildStarted +=
                new BuildStartedEventHandler(this.BuildStarted);
            eventSource.BuildFinished +=
                new BuildFinishedEventHandler(this.BuildFinished);
            eventSource.ProjectStarted +=
                new ProjectStartedEventHandler(this.ProjectStarted);
            eventSource.ProjectFinished +=
                new ProjectFinishedEventHandler(this.ProjectFinished);
            eventSource.TargetStarted +=
                new TargetStartedEventHandler(this.TargetStarted);
            eventSource.TargetFinished +=
                new TargetFinishedEventHandler(this.TargetFinished);
            eventSource.TaskStarted +=
                new TaskStartedEventHandler(this.TaskStarted);
            eventSource.TaskFinished +=
                new TaskFinishedEventHandler(this.TaskFinished);
            eventSource.ErrorRaised +=
                new BuildErrorEventHandler(this.BuildError);
            eventSource.WarningRaised +=
                new BuildWarningEventHandler(this.BuildWarning);
            eventSource.MessageRaised +=
                new BuildMessageEventHandler(this.BuildMessage);

        }
        public override void Shutdown() {
            File.WriteAllText(Filename, MdElements.ToMarkdown());
        }
        #endregion
        #region Logging handlers

        void BuildStarted(object sender, BuildStartedEventArgs e) {           
            AppendLine(string.Format("#Build Started {0}", e.Timestamp).ToMarkdownRawMarkdown());

            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                var r = from be in e.BuildEnvironment.Keys
                        select new {
                            Name = be,
                            Value = e.BuildEnvironment[be]
                        };

                AppendLine(r.ToMarkdownTable());

                AppendLine(e.ToPropertyValues().ToMarkdownTable());
            }

        }
        void BuildFinished(object sender, BuildFinishedEventArgs e) {
            AppendLine(string.Format("#Build Finished").ToMarkdownRawMarkdown());
            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine(e.ToPropertyValues().ToMarkdownTable().ToMarkdown().ToMarkdownRawMarkdown());

                if (e.BuildEventContext != null) {
                    AppendLine(e.BuildEventContext.ToPropertyValues().ToMarkdownTable().ToMarkdown().ToMarkdownRawMarkdown());
                }
            }

            AppendLine("Target summary".ToMarkdownSubHeader());
            var targetSummary = from t in this._targetsExecuted
                                orderby t.Value.TimeSpent descending
                                select new Tuple<string, int>(t.Value.Name, t.Value.TimeSpent.Milliseconds);

            AppendLine(targetSummary.ToList().ToMarkdownBarChart());

            AppendLine("Task summary".ToMarkdownSubHeader());
            var taskSummary = from t in this._taskExecuted
                              orderby t.Value.TimeSpent descending
                              select new Tuple<string, int>(t.Value.Name, t.Value.TimeSpent.Milliseconds);

            AppendLine(taskSummary.ToList().ToMarkdownBarChart());

            // add the TOC to the list of items to be logged
            // e.Succeeded
            // e.Message
            List<IMarkdownElement> toc = new List<IMarkdownElement>();
            toc.Add("Build Summary".ToMarkdownHeader());

            foreach (var project in this._projectsExecuted.OrderBy(p=>p.StartedArgs.Timestamp)) {
                string formatStr = @" - [{0}]({1}) | {2} | ```time={3} targets={4}```";

                ProjectFinishedEventArgs finishedArgs = project.FinishedArgs as ProjectFinishedEventArgs;
                string failStr = finishedArgs.Succeeded ? string.Empty : @"<font color=""red"">Failed</font>";

                string color = finishedArgs.Succeeded ? "green" : "red";

                string statusString = string.Format(
                    @"<font color=""{0}"">{1}</font>",
                    color,
                    finishedArgs.Succeeded ? "Succeeded" : "Failed");

                string targetNames = (project.StartedArgs as ProjectStartedEventArgs).TargetNames;
                if (string.IsNullOrEmpty(targetNames)) {
                    targetNames = "(default targets)";
                }

                string md = string.Format(
                                formatStr,                                
                                Path.GetFileName(project.Name),
                                this.GetLinkNameFor(project.StartedArgs as ProjectStartedEventArgs),
                                statusString,
                                string.Format("{0}s",project.TimeSpent.TotalSeconds),
                                targetNames
                                );

                toc.Add(md.ToMarkdownRawMarkdown());
            }
            toc.AddRange(MdElements);
            MdElements = toc;
        }
        private IMarkdownElement CreateProjectSummaryElement(ProjectStartedEventArgs startedArgs,ProjectFinishedEventArgs finishedArgs){
            string formatStr = @" - [{0}]({1}) | {2} | ```time={3} targets={4}```";

            string failStr = finishedArgs.Succeeded ? string.Empty : @"<font color=""red"">Failed</font>";

            string color = finishedArgs.Succeeded ? "green" : "red";

            string statusString = string.Format(
                @"<font color=""{0}"">{1}</font>",
                color,
                finishedArgs.Succeeded ? "Succeeded" : "Failed");

            string targetNames = (startedArgs as ProjectStartedEventArgs).TargetNames;
            if (string.IsNullOrEmpty(targetNames)) {
                targetNames = "(default targets)";
            }

            string md = string.Format(
                            formatStr,
                            Path.GetFileName(finishedArgs.ProjectFile),
                            this.GetLinkNameFor(startedArgs),
                            statusString,
                            string.Format("{0}s", finishedArgs.Timestamp),
                            targetNames
                            );
            return md.ToMarkdownRawMarkdown();
        }
        void ProjectStarted(object sender, ProjectStartedEventArgs e) {
            this._projectsStarted.Push(e);

            AppendLine(string.Format(@"<a name=""{0}"">&nbsp;</a>", this.GetLinkNameFor(e)).ToMarkdownRawMarkdown());
            AppendLine(string.Format("##Project Started:{0}\r\n", e.ProjectFile).ToMarkdownRawMarkdown());
            AppendLine(string.Format("_{0}_\r\n", e.Message.EscapeMarkdownCharacters()).ToMarkdownRawMarkdown());
            AppendLine(string.Format("```{0} | targets=({1}) | {2}```\r\n", e.Timestamp, e.TargetNames, e.ProjectFile).ToMarkdownRawMarkdown());

            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine("###Global properties".ToMarkdownRawMarkdown());
                AppendLine(e.GlobalProperties.ToMarkdownTable());

                AppendLine("####Initial Properties".ToMarkdownRawMarkdown());

                List<Tuple<string, string>> propsToDisplay = new List<Tuple<string, string>>();
                foreach (DictionaryEntry p in e.Properties) {
                    propsToDisplay.Add(new Tuple<string, string>(p.Key.ToString(), p.Value.ToString()));
                }
                AppendLine(propsToDisplay.ToMarkdownTable().WithHeaders(new string[] { "Name", "Value" }));
            }
        }
        void ProjectFinished(object sender, ProjectFinishedEventArgs e) {
            AppendLine(string.Format("##Project Finished:{0}", e.Message.EscapeMarkdownCharacters()).ToMarkdownRawMarkdown());

            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine(e.ToPropertyValues().ToMarkdownTable());
            }
            
            var startInfo = _projectsStarted.Pop();
            var execInfo = new ExecutionInfo(e.ProjectFile, startInfo, e);
            ExecutionInfo prevExecInfo;
            this._projectsExecutedMap.TryGetValue(e.ProjectFile, out prevExecInfo);
            if (prevExecInfo != null) {
                // shouldn't be found for projects but we can handle in either case
                execInfo.TimeSpent = execInfo.TimeSpent.Add(prevExecInfo.TimeSpent);

                var projToRemove = (from p in _projectsExecuted
                                    where p.Name.Equals(execInfo.Name)
                                    select p).ToList();

                foreach (var p in projToRemove) {
                    _projectsExecuted.Remove(p);
                }
            }

            _projectsExecutedMap[execInfo.Name] = execInfo;            
            _projectsExecuted.Add(execInfo);
        }

        void TargetStarted(object sender, TargetStartedEventArgs e) {
            _targetsStarted.Push(e);
            AppendLine(string.Format("####{0}", e.TargetName).ToMarkdownRawMarkdown());

            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine(e.ToPropertyValues().ToMarkdownTable());
            }
        }
        void TargetFinished(object sender, TargetFinishedEventArgs e) {
            var startInfo = _targetsStarted.Pop();

            var execInfo = new ExecutionInfo(startInfo.TargetName, startInfo, e);
            // see if the target is already in the executed list
            ExecutionInfo prevExecInfo;
            this._targetsExecuted.TryGetValue(e.TargetName, out prevExecInfo);

            if (prevExecInfo != null) {
                execInfo.TimeSpent = execInfo.TimeSpent.Add(prevExecInfo.TimeSpent);
            }

            this._targetsExecuted[execInfo.Name] = execInfo;
            string color = e.Succeeded ? "green" : "red";

            AppendLine(string.Format(
                "####<font color='{0}'>{1}</font> target finished",
                color,
                e.TargetName).ToMarkdownRawMarkdown());
            AppendLine(e.Message.ToMarkdownParagraph());

            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine(e.ToPropertyValues().ToMarkdownTable());
            }
        }
        void TaskStarted(object sender, TaskStartedEventArgs e) {
            _tasksStarted.Push(e);
            
            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine(string.Format("######Task Started:{0}", e.Message.EscapeMarkdownCharacters()).ToMarkdownRawMarkdown());
            }

            if (IsVerbosityAtLeast(LoggerVerbosity.Diagnostic)) {
                AppendLine(e.ToPropertyValues().ToMarkdownTable());
            }
        }

        void TaskFinished(object sender, TaskFinishedEventArgs e) {
            if (!e.Succeeded) {
                AppendLine(string.Format("<font color='red'>{0}</font> task failed.\r\n{1}",e.TaskName, e.Message).ToMarkdownRawMarkdown());
            }
            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine(string.Format("######Task Finished:{0}", e.Message.EscapeMarkdownCharacters()).ToMarkdownRawMarkdown());
                AppendLine(e.ToPropertyValues().ToMarkdownTable().ToMarkdown().ToMarkdownRawMarkdown());
            }
            var startInfo = _tasksStarted.Pop();
            var execInfo = new ExecutionInfo(startInfo.TaskName,startInfo, e);

            ExecutionInfo previousExecInfo;
            this._taskExecuted.TryGetValue(e.TaskName, out previousExecInfo);

            if (previousExecInfo != null) {
                execInfo.TimeSpent = execInfo.TimeSpent.Add(previousExecInfo.TimeSpent);
            }

            this._taskExecuted[execInfo.Name] = execInfo;
        }
        void BuildError(object sender, BuildErrorEventArgs e) {
            AppendLine(string.Format("###ERROR:<font color='red'>{0}</font>", e.Message.EscapeMarkdownCharacters()).ToMarkdownRawMarkdown());
            AppendLine(e.ToPropertyValues().ToMarkdownTable());
        }
        void BuildWarning(object sender, BuildWarningEventArgs e) {
            AppendLine(string.Format("###Warning:<font color='orange'>{0}</font>", e.Message.EscapeMarkdownCharacters()).ToMarkdownRawMarkdown());
            AppendLine(e.ToPropertyValues().ToMarkdownTable());
        }
        void BuildMessage(object sender, BuildMessageEventArgs e) {
            string formatStr = null;
            switch (e.Importance) {
                case MessageImportance.High:
                    formatStr = "\r\n{0} *{1}*";
                    break;
                case MessageImportance.Normal:
                case MessageImportance.Low:
                    formatStr = "\r\n{0} {1}";
                    break;
                default:
                    throw new LoggerException(string.Format("Unknown message importance {0}", e.Importance));
            }

            string msg = string.Format(formatStr, e.Message.EscapeMarkdownCharacters(), e.Timestamp.ToString().EscapeMarkdownCharacters());

            if (e.Importance != MessageImportance.Low || IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine(msg.ToMarkdownRawMarkdown());
            }
            
        }
        #endregion
        protected void AppendLine(MarkdownElement element) {
            MdElements.Add(element);
        }

        protected string GetLinkNameFor(ProjectStartedEventArgs startedEventArgs) {
            if (startedEventArgs == null) { throw new ArgumentNullException("startedEventArgs"); }

            List<long> hashCodes = new List<long> {
                startedEventArgs.ProjectFile.GetHashCode(),
                startedEventArgs.Timestamp.GetHashCode()
            };

            long code = hashCodes.Sum();
            
            return string.Format("{0}-{1}",Path.GetFileNameWithoutExtension(startedEventArgs.ProjectFile),code);
        }
    }
}
