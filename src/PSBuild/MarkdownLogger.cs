namespace PSBuild {
    using System.Text;
    using Microsoft.Build.Framework;
    using MarkdownLog;
    using System.Linq;
    using System.Collections.Generic;
    using System;
    using System.Collections;

    /// <summary>
    /// This class is simply for demonstration purposes, a better file logger to use is the
    /// Microsoft.Build.Engine.FileLogger class.
    /// 
    /// Author: Sayed Ibrahim Hashimi (sayed.hashimi@gmail.com)
    /// This class has not been throughly tested and is offered with no warranty.
    /// copyright Sayed Ibrahim Hashimi 2005
    /// </summary>
    public class MarkdownLogger : Microsoft.Build.Utilities.Logger {
        #region Fields
        private string _fileName;
        private StringBuilder _messages;
        private IDictionary<string, string> _paramaterBag;

        private Dictionary<string, ExecutionInfo> _targetsExecuted;
        private Stack<TargetStartedEventArgs> _targetsStarted;

        private Dictionary<string, ExecutionInfo> _taskExecuted;
        private Stack<TaskStartedEventArgs> _tasksStarted;
        #endregion

        public MarkdownLogger() {
            this._targetsExecuted = new Dictionary<string, ExecutionInfo>();
            this._targetsStarted = new Stack<TargetStartedEventArgs>();

            this._taskExecuted = new Dictionary<string, ExecutionInfo>();
            this._tasksStarted = new Stack<TaskStartedEventArgs>();
        }

        #region ILogger Members
        public override void Initialize(IEventSource eventSource) {
            _fileName = "build.log.md";
            _messages = new StringBuilder();

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

            this.InitializeParameters();
        }
        public override void Shutdown() {
            System.IO.File.WriteAllText(_fileName, _messages.ToString());
        }
        #endregion
        #region Logging handlers
        void BuildStarted(object sender, BuildStartedEventArgs e) {
            AppendLine(string.Format("#Build Started {0}", e.Timestamp));

            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                var r = from be in e.BuildEnvironment.Keys
                        select new {
                            Name = be,
                            Value = e.BuildEnvironment[be]
                        };

                AppendLine(r.ToMarkdownTable().ToMarkdown());

                AppendLine(e.ToPropertyValues().ToMarkdownTable().ToMarkdown());
            }

        }
        void BuildFinished(object sender, BuildFinishedEventArgs e) {
            AppendLine(string.Format("#Build Finished"));
            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine(e.ToPropertyValues().ToMarkdownTable().ToMarkdown());
            }

            AppendLine("Target summary".ToMarkdownSubHeader().ToMarkdown());
            var targetSummary = from t in this._targetsExecuted
                                orderby t.Value.TimeSpent descending
                                select new Tuple<string, int>(t.Value.Name, t.Value.TimeSpent.Milliseconds);

            AppendLine(targetSummary.ToList().ToMarkdownBarChart().ToMarkdown());

            AppendLine("Task summary".ToMarkdownSubHeader().ToMarkdown());
            var taskSummary = from t in this._taskExecuted
                              orderby t.Value.TimeSpent descending
                              select new Tuple<string, int>(t.Value.Name, t.Value.TimeSpent.Milliseconds);

            AppendLine(taskSummary.ToList().ToMarkdownBarChart().ToMarkdown());
        }
        void ProjectStarted(object sender, ProjectStartedEventArgs e) {
            AppendLine(string.Format("##Project Started:{0}\r\n", e.ProjectFile));
            AppendLine(string.Format("_{0}_\r\n", e.Message.EscapeMarkdownCharacters()));
            AppendLine(string.Format("```{0} | targets=({1}) | {2}```\r\n", e.Timestamp, e.TargetNames, e.ProjectFile));

            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine("###Global properties");
                AppendLine(e.GlobalProperties.ToMarkdownTable().ToMarkdown());

                AppendLine("####Initial Properties");

                List<Tuple<string, string>> propsToDisplay = new List<Tuple<string, string>>();
                foreach (DictionaryEntry p in e.Properties) {
                    propsToDisplay.Add(new Tuple<string, string>(p.Key.ToString(), p.Value.ToString()));
                }
                AppendLine(propsToDisplay.ToMarkdownTable().WithHeaders(new string[]{"Name","Value"}).ToMarkdown());
            }
        }
        void ProjectFinished(object sender, ProjectFinishedEventArgs e) {
            AppendLine(string.Format("##Project Finished:{0}", e.Message.EscapeMarkdownCharacters()));
            
            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine(e.ToPropertyValues().ToMarkdownTable().ToMarkdown());
            }
        }

        void TargetStarted(object sender, TargetStartedEventArgs e) {
            _targetsStarted.Push(e);
            AppendLine(string.Format("####{0}", e.TargetName));

            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine(e.ToPropertyValues().ToMarkdownTable().ToMarkdown());
            }
        }
        void TargetFinished(object sender, TargetFinishedEventArgs e) {
            var startInfo = _targetsStarted.Pop();

            var execInfo = new ExecutionInfo(startInfo.TargetName, startInfo, e);
            // see if the target is already in the executed list
            ExecutionInfo previoudExecInfo;
            this._targetsExecuted.TryGetValue(e.TargetName, out previoudExecInfo);

            if (previoudExecInfo != null) {
                execInfo.TimeSpent = execInfo.TimeSpent.Add(previoudExecInfo.TimeSpent);
            }

            this._targetsExecuted[execInfo.Name] = execInfo;
            string color = e.Succeeded ? "green" : "red";

            AppendLine(string.Format(
                "####<font color='{0}'>{1}</font> Target Finished",
                color,
                e.TargetName));

            AppendLine(e.Message.ToMarkdownParagraph().ToMarkdown());

            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine(e.ToPropertyValues().ToMarkdownTable().ToMarkdown());
            }
        }
        void TaskStarted(object sender, TaskStartedEventArgs e) {
            _tasksStarted.Push(e);
            
            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine(string.Format("######Task Started:{0}", e.Message.EscapeMarkdownCharacters()));
            }

            if (IsVerbosityAtLeast(LoggerVerbosity.Diagnostic)) {
                AppendLine(e.ToPropertyValues().ToMarkdownTable().ToMarkdown());
            }
        }

        void TaskFinished(object sender, TaskFinishedEventArgs e) {
            AppendLine(string.Format("######Task Finished:{0}", e.Message.EscapeMarkdownCharacters()));

            if (!e.Succeeded) {
                AppendLine(string.Format("<font color='red'>{0}</font> task failed.\r\n{1}", e.Message));
            }

            if (IsVerbosityAtLeast(LoggerVerbosity.Detailed)) {
                AppendLine(e.ToPropertyValues().ToMarkdownTable().ToMarkdown());
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
            AppendLine(string.Format("###ERROR:<font color='red'>{0}</font>", e.Message.EscapeMarkdownCharacters()));
            AppendLine(e.ToPropertyValues().ToMarkdownTable().ToMarkdown());
        }
        void BuildWarning(object sender, BuildWarningEventArgs e) {
            AppendLine(string.Format("###Warning:<font color='orange'>{0}</font>", e.Message.EscapeMarkdownCharacters()));
            AppendLine(e.ToPropertyValues().ToMarkdownTable().ToMarkdown());
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
                AppendLine(msg);
            }
        }
        #endregion
        protected void AppendLine(string line) {
            _messages.AppendLine(line);
        }


        /// <summary>
        /// This will read in the parameters and process them.
        /// The parameter string should look like: paramName1=val1;paramName2=val2;paramName3=val3
        /// This method will also cause the known parameter properties of this class to be set if they
        /// are present.
        /// </summary>
        protected virtual void InitializeParameters() {
            try {
                this._paramaterBag = new Dictionary<string, string>();
                if (!string.IsNullOrEmpty(Parameters)) {
                    foreach (string paramString in this.Parameters.Split(";".ToCharArray())) {
                        string[] keyValue = paramString.Split("=".ToCharArray());
                        if (keyValue == null || keyValue.Length < 2) {
                            continue;
                        }
                        this.ProcessParam(keyValue[0].ToLower(), keyValue[1]);
                    }
                }
            }
            catch (Exception e) {
                throw new LoggerException("Unable to initialize parameterss; message=" + e.Message, e);
            }
        }

        /// <summary>
        /// Method that will process the parameter value. If either <code>name</code> or
        /// <code>value</code> is empty then this parameter will not be processed.
        /// </summary>
        /// <param name="name">name of the paramater</param>
        /// <param name="value">value of the parameter</param>
        protected virtual void ProcessParam(string name, string value) {
            try {
                if (!string.IsNullOrEmpty(name) &&
                        !string.IsNullOrEmpty(value)) {
                    //add to param bag so subclasses have easy method to fetch other parameter values
                    AddToParameters(name, value);
                    switch (name.Trim().ToUpper()) {
                        case ("LOGFILE"):
                        case ("L"):
                            this._fileName = value;
                            break;

                        case ("VERBOSITY"):
                        case ("V"):
                            ProcessVerbosity(value);
                            break;
                    }
                }
            }
            catch (LoggerException /*le*/) {
                throw;
            }
            catch (Exception e) {
                string message = "Unable to process parameters;[name=" + name + ",value=" + value + " message=" + e.Message;
                throw new LoggerException(message, e);
            }
        }
        /// <summary>
        /// This will set the verbosity level from the parameter
        /// </summary>
        /// <param name="level"></param>
        protected virtual void ProcessVerbosity(string level) {
            if (!string.IsNullOrEmpty(level)) {

                switch (level.Trim().ToUpper()) {
                    case ("QUIET"):
                    case ("Q"):
                        this.Verbosity = LoggerVerbosity.Quiet;
                        break;

                    case ("MINIMAL"):
                    case ("M"):
                        this.Verbosity = LoggerVerbosity.Minimal;
                        break;

                    case ("NORMAL"):
                    case ("N"):
                        this.Verbosity = LoggerVerbosity.Normal;
                        break;

                    case ("DETAILED"):
                    case ("D"):
                        this.Verbosity = LoggerVerbosity.Detailed;
                        break;

                    case ("DIAGNOSTIC"):
                    case ("DIAG"):
                        this.Verbosity = LoggerVerbosity.Diagnostic;
                        break;

                    default:
                        throw new LoggerException("Unable to process the verbosity: " + level);
                }
            }
        }

        /// <summary>
        /// Adds the given name & value to the <code>_parameterBag</code>.
        /// If the bag already contains the name as a key, this value will replace the previous value.
        /// </summary>
        /// <param name="name">name of the parameter</param>
        /// <param name="value">value for the paramter</param>
        protected virtual void AddToParameters(string name, string value) {
            if (name == null) { throw new ArgumentNullException("name"); }
            if (value == null) { throw new ArgumentException("value"); }

            string paramKey = name.ToUpper();
            try {
                if (_paramaterBag.ContainsKey(paramKey)) { _paramaterBag.Remove(paramKey); }

                _paramaterBag.Add(paramKey, value);
            }
            catch (Exception e) {
                throw new LoggerException("Unable to add to parameters bag", e);
            }
        }
        /// <summary>
        /// This can be used to get the values of parameter that this class is not aware of.
        /// If the value is not present then string.Empty is returned.
        /// </summary>
        /// <param name="name">name of the parameter to fetch</param>
        /// <returns></returns>
        protected virtual string GetParameterValue(string name) {
            if (name == null) { throw new ArgumentNullException("name"); }

            string paramName = name.ToUpper();

            string value = null;
            if (_paramaterBag.ContainsKey(paramName)) {
                value = _paramaterBag[paramName];
            }

            return value;
        }
    }
}
