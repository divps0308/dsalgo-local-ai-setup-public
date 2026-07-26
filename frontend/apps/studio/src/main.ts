import { mount } from "svelte";
import "../../../shared/styles.css";
import App from "./App.svelte";

mount(App, { target: document.getElementById("app")! });
