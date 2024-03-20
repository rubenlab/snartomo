import { createRouter, createWebHashHistory } from "vue-router";
import HomeView from "../views/PACEView.vue";

const router = createRouter({
  history: createWebHashHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: "/",
      name: "home",
      component: HomeView,
    },
    {
      path: "/classic",
      name: "classic",
      // route level code-splitting
      // this generates a separate chunk (About.[hash].js) for this route
      // which is lazy-loaded when the route is visited.
      component: () => import("../views/ClassicView.vue"),
    },
    {
      path: "/framecalc",
      name: "framecalc",
      // route level code-splitting
      // this generates a separate chunk (About.[hash].js) for this route
      // which is lazy-loaded when the route is visited.
      component: () => import("../views/FramecalcView.vue"),
    },
  ],
});

export default router;
