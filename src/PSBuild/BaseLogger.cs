namespace PSBuild {
    using System.Text;
    using Microsoft.Build.Framework;
    using MarkdownLog;
    using System.Linq;
    using System.Collections.Generic;
    using System;
    using System.Collections;
    using Microsoft.Build.Utilities;

    /// <summary>
    /// This class is simply for demonstration purposes, a better file logger to use is the
    /// Microsoft.Build.Engine.FileLogger class.
    /// 
    /// Author: Sayed Ibrahim Hashimi (sayed.hashimi@gmail.com)
    /// This class has not been throughly tested and is offered with no warranty.
    /// copyright Sayed Ibrahim Hashimi 2005
    /// </summary>
    public class BaseLogger : Logger {
        #region Fields
        protected string Filename { get; set; }
        private IDictionary<string, string> _paramaterBag;
        #endregion

        public override void Initialize(IEventSource eventSource) {
            this.InitializeParameters();
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
                            this.Filename = value;
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
