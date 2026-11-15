import { Component } from "react";
import type { ErrorInfo, ReactNode } from "react";

type Props = { children: ReactNode };
type State = { error: Error | null };

export default class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error("WebUI render failed", error, info);
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div className="fatal-screen" role="alert">
        <h1>页面渲染失败</h1>
        <p>{this.state.error.message}</p>
        <button className="button primary" onClick={() => window.location.reload()}>
          重新加载
        </button>
      </div>
    );
  }
}
