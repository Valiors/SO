#include <minix/drivers.h>
#include <minix/chardriver.h>
#include <stdio.h>
#include <stdlib.h>
#include <minix/ds.h>
#include <minix/ioctl.h>
#include <sys/ioc_hello_queue.h>
#include "hello_queue.h"

static int queue_open(devminor_t minor, int access, endpoint_t user_endpt);

static int queue_close(devminor_t minor);

static ssize_t queue_read(devminor_t minor, u64_t position, endpoint_t endpt,
                          cp_grant_id_t grant, size_t size,
                          int flags, cdev_id_t id);

static ssize_t queue_write(devminor_t minor, u64_t position, endpoint_t endpt,
                           cp_grant_id_t grant, size_t size,
                           int flags, cdev_id_t id);

static int queue_ioctl(devminor_t minor, unsigned long request,
                       endpoint_t endpt, cp_grant_id_t grant, int flags,
                       endpoint_t user_endpt, cdev_id_t id);

/* SEF functions and variables. */
static void sef_local_startup(void);

static int sef_cb_init(int type, sef_init_info_t *info);

static int sef_cb_lu_state_save(int);

static int lu_state_restore(void);

static struct chardriver queue_tab = {
        .cdr_open = queue_open,
        .cdr_close = queue_close,
        .cdr_read = queue_read,
        .cdr_write = queue_write,
        .cdr_ioctl = queue_ioctl
};

static char *buffer; // Pointer to beginning of the buffer.
static u32_t buffer_size; // Size of the buffer.
static u32_t begin; // Index of begin of the queue.
static u32_t end; // Index past the last one element of the queue.

/* Changes size of the buffer to new_size. */
static void resize_buffer(size_t new_size) {
    char *nb = realloc(buffer, new_size);

    if (nb) {
        buffer = nb;
        buffer_size = new_size;
    } else {
        free(buffer);
        printf("Memory allocation failed!\n");
        exit(1);
    }
}

/* Moves queue from [begin + offset, end) to [0, end - begin - offset). */
static void move_queue(size_t offset) {
    for (size_t i = begin + offset; i < end; i++) {
        buffer[i - begin - offset] = buffer[i];
    }

    begin = 0;
    end = end - begin - offset;
}

/* Makes sure that buffer is at least required_size. */
static void reserve_space(size_t required_size) {
    if (buffer_size < required_size) {
        while (buffer_size < required_size) {
            buffer_size *= 2;
        }

        resize_buffer(buffer_size);
    }
}

/* Restores buffer and queue to initial state. */
static void xyz_reset(void) {
    static char c[] = {'x', 'y', 'z'};

    resize_buffer(DEVICE_SIZE);

    for (size_t i = 0; i < buffer_size; i++) {
        buffer[i] = c[i % 3];
    }

    begin = 0;
    end = buffer_size;
}

static int do_hqiocres(void) {
    xyz_reset();
    return OK;
}

static int do_hqiocset(endpoint_t endpt, cp_grant_id_t grant) {
    if (MSG_SIZE == 0) {
        return OK;
    }

    char *c;

    if (!(c = malloc(MSG_SIZE))) {
        free(buffer);
        printf("Memory allocation failed!\n");
        exit(1);
    }

    int r = sys_safecopyfrom(endpt, grant, 0, (vir_bytes)c, MSG_SIZE);
    if (r != OK) {
        free(c);
        return r;
    }

    reserve_space(MSG_SIZE);

    if (MSG_SIZE > end) {
        end = MSG_SIZE;
    }

    for (size_t i = end - MSG_SIZE; i < end; i++) {
        buffer[i] = c[i + MSG_SIZE - end];
    }

    free(c);
    return OK;
}

static int do_hqiocxch(endpoint_t endpt, cp_grant_id_t grant) {
    char c[2];

    int r = sys_safecopyfrom(endpt, grant, 0, (vir_bytes)c, 2);
    if (r != OK) {
        return r;
    }

    for (size_t i = begin; i < end; i++) {
        if (buffer[i] == c[0]) {
            buffer[i] = c[1];
        }
    }

    return OK;
}

static int do_hqiocdel(void) {
    size_t it = 0;

    for (size_t i = begin; i < end; i++) {
        if ((i - begin) % 3 != 2) {
            buffer[it] = buffer[i];
            it++;
        }
    }

    begin = 0;
    end = it;

    return OK;
}

static int queue_open(devminor_t UNUSED(minor), int UNUSED(access),
                    endpoint_t UNUSED(user_endpt)) {
    return OK;
}

static int queue_close(devminor_t UNUSED(minor)) {
    return OK;
}

static ssize_t queue_read(devminor_t UNUSED(minor), u64_t UNUSED(position),
                          endpoint_t endpt, cp_grant_id_t grant, size_t size,
                          int UNUSED(flags), cdev_id_t UNUSED(id)) {

    if (end - begin < size) {
        size = end - begin;
    }

    if (size == 0) {
        return 0;
    }

    int r = sys_safecopyto(endpt, grant, 0, (vir_bytes)(buffer + begin), size);
    if (r != OK) {
        return r;
    }

    move_queue(size);

    if (end - begin <= buffer_size / 4 && buffer_size > 1) {
        resize_buffer(buffer_size / 2);
    }

    return size;
}

static ssize_t queue_write(devminor_t UNUSED(minor), u64_t UNUSED(position),
                           endpoint_t endpt, cp_grant_id_t grant, size_t size,
                           int UNUSED(flags), cdev_id_t UNUSED(id)) {

    reserve_space(end + size);

    if (size == 0) {
        return 0;
    }

    int r = sys_safecopyfrom(endpt, grant, 0, (vir_bytes)(buffer + end), size);
    if (r != OK) {
        return r;
    }

    end = end + size;

    return size;
}

static int queue_ioctl(devminor_t UNUSED(minor), unsigned long request,
                       endpoint_t endpt, cp_grant_id_t grant, int UNUSED(flags),
                       endpoint_t UNUSED(user_endpt), cdev_id_t UNUSED(id)) {
    switch (request) {
        case HQIOCRES:
            return do_hqiocres();
        case HQIOCSET:
            return do_hqiocset(endpt, grant);
        case HQIOCXCH:
            return do_hqiocxch(endpt, grant);
        case HQIOCDEL:
            return do_hqiocdel();
        default:
            return ENOTTY;
    }
}

static int sef_cb_lu_state_save(int UNUSED(state)) {
    /* Save the state. */
    ds_publish_mem("buffer_helloq", buffer, buffer_size, DSF_OVERWRITE);

    ds_publish_u32("begin_helloq", begin, DSF_OVERWRITE);
    ds_publish_u32("end_helloq", end, DSF_OVERWRITE);
    ds_publish_u32("size_helloq", buffer_size, DSF_OVERWRITE);

    return OK;
}

static int lu_state_restore(void) {
    /* Restore the state. */
    ds_retrieve_u32("begin_helloq", &begin);
    ds_retrieve_u32("end_helloq", &end);
    ds_retrieve_u32("size_helloq", &buffer_size);

    if (!(buffer = malloc(buffer_size))) {
        printf("Memory allocation failed!\n");
        exit(1);
    }

    size_t len = buffer_size;
    ds_retrieve_mem("buffer_helloq", buffer, &len);

    ds_delete_mem("buffer_helloq");
    ds_delete_u32("begin_helloq");
    ds_delete_u32("end_helloq");
    ds_delete_u32("size_helloq");

    return OK;
}

static void sef_local_startup(void) {
    /* Init callbacks registration. */
    sef_setcb_init_fresh(sef_cb_init);
    sef_setcb_init_lu(sef_cb_init);
    sef_setcb_init_restart(sef_cb_init);

    /* Register live update callbacks. */
    /* - Agree to update immediately when LU is requested in a valid state. */
    sef_setcb_lu_prepare(sef_cb_lu_prepare_always_ready);
    /* - Support live update starting from any standard state. */
    sef_setcb_lu_state_isvalid(sef_cb_lu_state_isvalid_standard);
    /* - Register a custom routine to save the state. */
    sef_setcb_lu_state_save(sef_cb_lu_state_save);

    /* Let SEF perform startup. */
    sef_startup();
}

static int sef_cb_init(int type, sef_init_info_t *UNUSED(info)) {
    /* Initialize the hello driver. */
    int do_announce_driver = TRUE;

    switch (type) {
        case SEF_INIT_FRESH:
            buffer = NULL;
            xyz_reset();
            break;
        case SEF_INIT_LU:
            do_announce_driver = FALSE;
            lu_state_restore();
            break;
        case SEF_INIT_RESTART:
            lu_state_restore();
            break;
    }

    /* Announce we are up when necessary. */
    if (do_announce_driver) {
        chardriver_announce();
    }

    /* Initialization completed successfully. */
    return OK;
}

/* Frees allocated resources. */
static void cleanup(void) {
    free(buffer);
}

int main(void) {
    sef_local_startup();

    chardriver_task(&queue_tab);

    cleanup();

    return OK;
}
