includes TokenMachineRuntime;

// TODO: fix memcpy's to only copy the used portion of the message.

#define TOKBUFFER_LENGTH 10 // Buffer 10 incoming messages. Should be around 320 bytes.

module BasicTMCommM {
  provides {
    interface TMComm[uint8_t id];
    interface StdControl;
    //    interface ReceiveMsg;

    // I don't actually want to expose these, but I don't know how to
    // make private commands.
    async command result_t add_msg(TOS_MsgPtr token);     
    async command result_t pop_msg(TOS_MsgPtr dest);
    async command TOS_Msg peek_nth_msg(uint16_t indx);

    command void print_cache();
    async command int16_t num_tokens();
   }
  uses {

    // This is the output object produced by my Regiment compiler.
    interface TMModule;

    interface Timer;
    interface ReceiveMsg[uint8_t id];
    interface SendMsg[uint8_t id];
    interface Random;
  }
} implementation {

  TOS_Msg cached_token;
  
  TOS_MsgPtr currently_processing;
  TOS_Msg temp_msg;

  // This is a FIFO for storing incoming messages, implemented as a wrap-around buffer.
  TOS_Msg token_in_buffer[TOKBUFFER_LENGTH];

  TOS_Msg token_out_buffer; //[TOKBUFFER_LENGTH];
  bool send_pending; //[TOKBUFFER_LENGTH];

  // in_buffer_start is the position of the first element in the fifo.
  int16_t in_buffer_start;
  // in_buffer_end is the position of the last element, or -1 if there are
  // no elements in the fifo.
  int16_t in_buffer_end;

  task void tokenhandler () {
    atomic { // Access in_buffer_end/in_buffer_start
      if ( in_buffer_end == -1 ) {
	dbg(DBG_USR1, "TM BasicTMComm: tokenhandler: NO messages available.\n"); 	
      } else {
	if ( call pop_msg(&temp_msg) ) {
	  currently_processing = &temp_msg;
	  call TMModule.process_token(&temp_msg); // Do nothing with returned pointer.
	}
      }
    }
  }

  // Add a message to the token_in_buffer if there's room available.
  async command result_t add_msg(TOS_MsgPtr token) {    
    result_t res;
    atomic {    
//      if ( (in_buffer_start == 0 && in_buffer_end == (TOKBUFFER_LENGTH - 1)) || 	 
//	   (in_buffer_start != 0 && in_buffer_end == (in_buffer_start - 1)) ) {
      if ( call num_tokens() == TOKBUFFER_LENGTH ) {
	dbg(DBG_USR1, "TM BasicTMComm: cache full; cannot add token %d->%d\n", in_buffer_start, in_buffer_end);
	res = FAIL;
      } else {
	if ( in_buffer_end == -1 ) { in_buffer_end = in_buffer_start; }
	else { in_buffer_end++; }
	//	dbg(DBG_USR1, "TM BasicTMComm: Adding token payload at %d, origin:%d \n", 
	//	    in_buffer_end, payload.origin);	
	
	//memcpy(token_in_buffer + in_buffer_end, &payload, sizeof(TOS_Msg));	
	token_in_buffer[in_buffer_end] = *token;
	res = SUCCESS; 
      }
    }
    return res;
  }

  // Raisse error if there's no payload in the FIFO: 
  async command result_t pop_msg(TOS_MsgPtr dest) {
    atomic {
      if ( in_buffer_end == -1 ) {
	// raise error!
      } else {      
	memcpy(dest,token_in_buffer + in_buffer_start, sizeof(TOS_Msg));
	//dest = token_in_buffer[in_buffer_start];

	// If we're popping the last one, then it's empty after this:
	if (in_buffer_start == in_buffer_end) { 
	  in_buffer_end = -1; 
	  in_buffer_start = 0;
	} else {
	  in_buffer_start++;
	  if (in_buffer_start == TOKBUFFER_LENGTH) { in_buffer_start = 0; }
	}
      }
    }
    return SUCCESS;
  }
  
  // This is for abstracting over the annoying wrap around buffer and
  // accessing the nth element in the FIFO, where 0 is the next item
  // to be popped.
  async command TOS_Msg peek_nth_msg(uint16_t indx) {
    TOS_Msg ret_msg;
    atomic { 
      if ( indx >= (call num_tokens()) ) {
	// raise error!
      } else {
	indx += in_buffer_start;
	if ( indx >= TOKBUFFER_LENGTH ) { indx -= TOKBUFFER_LENGTH; }	
	//memcpy((&ret_msg),token_in_buffer + indx, sizeof(TOS_Msg));
	ret_msg = token_in_buffer[indx];
      }
    }
    return ret_msg;
  }


  // This is another helper method that abstracts over the obnoxious
  // start/end indices.
  async command int16_t num_tokens(){ 
    int16_t res;
    atomic { // Access in_buffer_end/in_buffer_start
      if (in_buffer_end == -1) { 
	res = 0;
      } else if (in_buffer_end >= in_buffer_start) {
	res = (1 + in_buffer_end - in_buffer_start);
      } else {
	res = (TOKBUFFER_LENGTH + 1 + in_buffer_end - in_buffer_start); // TEST THIS
      }
    }
    return res;
  }
  
  // This is a debugging function.
  command void print_cache() {
    int16_t i,j;

    atomic { // The token_in_buffer had better stay still while we print it out.

      dbg(DBG_USR1, "TM BasicTMComm: CONTENTS OF BUFFER, #tokens=%d start-end:%d/%d\n", 
	  call num_tokens(), in_buffer_start, in_buffer_end);
	  //	  99, in_buffer_start, in_buffer_end);
      
      for (i=0; i < call num_tokens(); i++) {
	j = i + in_buffer_start;
	if (j >= TOKBUFFER_LENGTH) { j -= TOKBUFFER_LENGTH; }
	
	/*	dbg(DBG_USR1, "TM BasicTMComm:   %d/%d: par:%d orig:%d  time:%d count:%d \n", 
	    i, j, 
	    token_in_buffer[j].origin,    token_in_buffer[j].parent, 
	    token_in_buffer[j].timestamp, token_in_buffer[j].counter);
	*/
      }
    }
  }

  command result_t StdControl.init() {
    atomic {
      in_buffer_start = 0;
      in_buffer_end = -1;
      currently_processing = NULL;
    }
   
    /*    temp_msg.origin = 91;
    temp_msg.parent = 92;
    temp_msg.timestamp = 93;
    temp_msg.counter = 94;*/

    dbg(DBG_USR1, "TM BasicTMCommM: Initializing, buffersize:%d, tokdatalen:%d  rettoklen:%d\n", 
	TOKBUFFER_LENGTH, TOK_DATA_LENGTH, RETURNTOK_DATA_LENGTH );

    return call Random.init();
  }

  command result_t StdControl.start() {
    return call Timer.start(TIMER_REPEAT, 3000);
  }
  command result_t StdControl.stop() {
    return call Timer.stop();
  }

  // Hope this gets statically wired and inlined 
  command result_t TMComm.emit[uint8_t id](uint16_t address, uint8_t length, TOS_MsgPtr msg) {
    TM_Payload* payload;
   
    if (send_pending) {
      return FAIL;
    } else {
      send_pending = TRUE;
      dbg(DBG_USR1, "TM BasicTMCommM: Emitting message of length:%d, orig:%d, type:%d/%d\n", 
	  msg->length, TOS_LOCAL_ADDRESS, msg->type, id);
      memcpy(&token_out_buffer, msg, sizeof(TOS_Msg));

      payload = (TM_Payload*)token_out_buffer.data;

      // Since this is an emisson, set the origin to *US*.
      payload->origin = TOS_LOCAL_ADDRESS;
      payload->parent = TOS_LOCAL_ADDRESS;
      payload->timestamp = 999; // TODO FIXME
      payload->counter = 1; // The nodes to receive this are hopcount 1.
      token_out_buffer.type = id;      
      return call SendMsg.send[id](address, length, &token_out_buffer);
    }
  }

  //  command result_t TMComm.relay[uint8_t id](uint16_t address, uint8_t length, TOS_MsgPtr msg) {
  command result_t TMComm.relay[uint8_t id]() {
    TM_Payload* payload;

    if ( NULL == currently_processing ) 
      return FAIL;

    if (send_pending) {
      return FAIL;
    } else {
      send_pending = TRUE;
      memcpy(&token_out_buffer, currently_processing, sizeof(TOS_Msg));
      payload = (TM_Payload*)token_out_buffer.data;

      dbg(DBG_USR1, "TM BasicTMCommM: Relaying message of length:%d, orig:%d, par:%d, type:%d/%d\n", 
	currently_processing->length, payload->origin, payload->parent, currently_processing->type, id);

      payload->parent = TOS_LOCAL_ADDRESS;
      //payload->timestamp = 999; // TODO FIXME
      payload->counter++; // Increment the hopcount!
      token_out_buffer.type = id;      
      return call SendMsg.send[id](TOS_BCAST_ADDR, token_out_buffer.length, &token_out_buffer);
    }
  }

  // Here's the tricky part.
  command result_t TMComm.return_home[uint8_t id](uint16_t address, uint8_t length, 
						  TOS_MsgPtr msg, uint16_t seed, uint16_t aggr) {


    return SUCCESS;
  }

  command TOS_MsgPtr TMComm.get_cached[uint8_t id]() {
    return &cached_token;
  }

  // I don't think I really want this in the interface:
  command result_t TMComm.set_cached[uint8_t id](TOS_MsgPtr newtok) {
    // This copies the data over.
    cached_token = *newtok;
    return SUCCESS;
  }

  event result_t Timer.fired() {
    /* // Add random messages:
    ((TM_Payload*)temp_msg.data)->origin = call Random.rand();
    ((TM_Payload*)temp_msg.data)->parent = call Random.rand();
    ((TM_Payload*)temp_msg.data)->timestamp = call num_tokens();
    ((TM_Payload*)temp_msg.data)->counter = (uint8_t)call Random.rand();
    */
    //    call add_msg(&temp_msg);

    call print_cache();

    // dbg(DBG_USR1, "TM BasicTMCommM: Timer Fired\n");
    return SUCCESS;
  }

  event result_t SendMsg.sendDone[uint8_t sent_id](TOS_MsgPtr msg, bool success) {
    // dbg(DBG_USR1, "TM BasicTMCommM: Done sending type: %d\n", msg->type);
    send_pending = FALSE;
    
    return SUCCESS;
  }
  
  event TOS_MsgPtr ReceiveMsg.receive[uint8_t id](TOS_MsgPtr msg) {
    // Post the token handler.
    call add_msg(msg);
    post tokenhandler();
    //return signal TMComm.receive[id](msg);
    return msg;
  }

  // This should never fire.  In fact, maybe I should signal an error here.
  //default event TOS_MsgPtr TMComm.receive[uint8_t id](TOS_MsgPtr msg) { return msg; }
}
